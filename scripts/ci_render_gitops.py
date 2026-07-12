#!/usr/bin/env python3
"""Render GitOps manifests per Application (kustomize + helm template) for CI preflight."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_MAP = {
    "https://charts.jetstack.io": "jetstack",
    "https://istio-release.storage.googleapis.com/charts": "istio",
    "https://prometheus-community.github.io/helm-charts": "prometheus-community",
    "https://kyverno.github.io/kyverno": "kyverno",
    "https://argoproj.github.io/argo-helm": "argo",
}

METALLB_URL = (
    "https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml"
)


def load_install_order(repo_root: Path) -> list[str]:
    order_file = repo_root / "scripts" / "gitops-install-order.sh"
    order: list[str] = []
    in_array = False
    for line in order_file.read_text(encoding="utf-8").splitlines():
        if "GITOPS_INSTALL_ORDER=(" in line:
            in_array = True
            continue
        if in_array:
            stripped = line.strip()
            if stripped == ")":
                break
            if stripped and not stripped.startswith("#"):
                order.append(stripped)
    if not order:
        raise ValueError(f"No install order found in {order_file}")
    return order


def load_applications(apps_file: Path) -> dict[str, dict]:
    apps: dict[str, dict] = {}
    with apps_file.open(encoding="utf-8") as fh:
        for doc in yaml.safe_load_all(fh):
            if doc and doc.get("kind") == "Application":
                apps[doc["metadata"]["name"]] = doc
    return apps


def helm_repo_add(name: str, url: str) -> None:
    listed = subprocess.run(
        ["helm", "repo", "list"], capture_output=True, text=True, check=False
    )
    if name in listed.stdout:
        return
    subprocess.run(["helm", "repo", "add", name, url], check=True, stdout=subprocess.DEVNULL)


def setup_helm_repos() -> None:
    for url, name in REPO_MAP.items():
        helm_repo_add(name, url)
    subprocess.run(["helm", "repo", "update"], check=True, stdout=subprocess.DEVNULL)


def render_kustomize(repo_root: Path, rel_path: str, out_path: Path) -> None:
    full = repo_root / rel_path
    if not full.is_dir():
        raise FileNotFoundError(f"GitOps path not found: {rel_path}")
    result = subprocess.run(
        ["kustomize", "build", str(full)],
        check=True,
        capture_output=True,
        text=True,
    )
    out_path.write_text(result.stdout, encoding="utf-8")


def render_helm(app: dict, out_path: Path) -> None:
    src = app["spec"]["source"]
    name = app["metadata"]["name"]
    repo_url = src["repoURL"]
    chart = src["chart"]
    repo = REPO_MAP.get(repo_url)
    if not repo:
        raise ValueError(f"Unknown Helm repo URL for {name}: {repo_url}")
    helm_cfg = src.get("helm") or {}
    release = helm_cfg.get("releaseName", name)
    values = helm_cfg.get("values", "") or ""
    namespace = app.get("spec", {}).get("destination", {}).get("namespace", "default")
    cmd = [
        "helm",
        "template",
        release,
        f"{repo}/{chart}",
        "--namespace",
        namespace,
    ]
    values_file = None
    if values.strip():
        fd, values_path = tempfile.mkstemp(prefix=f"helm-values-{name}-", suffix=".yaml")
        os.close(fd)
        values_file = Path(values_path)
        values_file.write_text(values, encoding="utf-8")
        cmd.extend(["-f", str(values_file)])
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        out_path.write_text(result.stdout, encoding="utf-8")
    finally:
        if values_file:
            values_file.unlink(missing_ok=True)


def render_applications(
    repo_root: Path,
    env: str,
    output_dir: Path,
    *,
    include_bootstrap: bool = False,
    include_metallb: bool = False,
) -> list[str]:
    apps_file = repo_root / "gitops" / "clusters" / env / "applications.yaml"
    apps = load_applications(apps_file)
    order = load_install_order(repo_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    needs_helm = any(
        apps[name]["spec"]["source"].get("chart")
        for name in order
        if name in apps
    )
    if needs_helm or include_bootstrap:
        setup_helm_repos()

    rendered: list[str] = []
    for app_name in order:
        if app_name not in apps:
            raise KeyError(f"Application {app_name!r} missing from {apps_file}")
        app = apps[app_name]
        src = app["spec"]["source"]
        out_path = output_dir / f"{app_name}.yaml"
        if src.get("path"):
            render_kustomize(repo_root, src["path"], out_path)
        elif src.get("chart"):
            render_helm(app, out_path)
        else:
            raise ValueError(f"Application {app_name} has no path or chart source")
        rendered.append(app_name)

    if include_bootstrap:
        bootstrap_values = repo_root / "hack" / "argocd" / "bootstrap-values.yaml"
        out = output_dir / "argocd-bootstrap.yaml"
        result = subprocess.run(
            [
                "helm",
                "template",
                "argocd",
                "argo/argo-cd",
                "--namespace",
                "argocd",
                "-f",
                str(bootstrap_values),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        out.write_text(result.stdout, encoding="utf-8")
        rendered.append("argocd-bootstrap")

    if include_metallb:
        out = output_dir / "metallb.yaml"
        subprocess.run(["curl", "-fsSL", METALLB_URL, "-o", str(out)], check=True)
        rendered.append("metallb")

    return rendered


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default="staging")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include-bootstrap", action="store_true")
    parser.add_argument("--include-metallb", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    try:
        names = render_applications(
            repo_root,
            args.env,
            args.output,
            include_bootstrap=args.include_bootstrap,
            include_metallb=args.include_metallb,
        )
    except (subprocess.CalledProcessError, OSError, ValueError) as exc:
        print(f"ERROR: render failed: {exc}", file=sys.stderr)
        return 1

    for name in names:
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
