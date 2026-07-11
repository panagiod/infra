# Bootstrap guide

Step-by-step instructions to provision staging and prod on AWS and verify the platform.

## 1. Remote state (one-time)

Create resources in your AWS account:

```bash
export AWS_REGION=us-east-1
export TF_STATE_BUCKET=your-org-terraform-state
export TF_LOCK_TABLE=your-org-terraform-locks

aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION"
aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name "$TF_LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
```

Copy and edit backend config for each environment:

```bash
cp terraform/environments/staging/backend.hcl.example terraform/environments/staging/backend.hcl
cp terraform/environments/prod/backend.hcl.example terraform/environments/prod/backend.hcl
```

## 2. Environment variables

```bash
cp terraform/environments/staging/terraform.tfvars.example terraform/environments/staging/terraform.tfvars
cp terraform/environments/prod/terraform.tfvars.example terraform/environments/prod/terraform.tfvars
```

| Variable | Staging example | Prod example |
|----------|-----------------|--------------|
| `cluster_name` | `infra-staging` | `infra-prod` |
| `kubernetes_version` | `1.29` | `1.29` |
| `node_instance_types` | `["t3.large"]` | `["m6i.large"]` |
| `node_desired_size` | `2` | `3` |
| `single_nat_gateway` | `true` | `false` |
| `gitops_repo_url` | `https://github.com/panagiod/infra` | same |

## 3. Apply Terraform

**Staging first:**

```bash
cd terraform/environments/staging
terraform init -backend-config=backend.hcl

# First apply creates VPC + EKS; second apply installs Helm addons (Argo CD, ALB controller).
terraform apply -target=module.vpc -target=module.eks
terraform plan -out=tfplan
terraform apply tfplan
```

**Then prod:**

```bash
cd terraform/environments/prod
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

## 4. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name infra-staging
aws eks update-kubeconfig --region us-east-1 --name infra-prod
```

## 5. Verify Argo CD

Argo CD is installed by the EKS module bootstrap Helm release.

```bash
kubectl -n argocd get pods
kubectl -n argocd get applications
```

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Port-forward UI:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080
```

The root application `cluster-root` syncs platform components and `mtls-demo`.

## 6. Verify platform

```bash
kubectl -n cert-manager get pods
kubectl -n istio-system get pods
kubectl -n monitoring get pods
kubectl get clusterissuer
kubectl -n istio-system get peerauthentication
```

## 7. Verify mTLS demo

```bash
kubectl -n mtls-demo get pods
kubectl -n mtls-demo exec deploy/frontend -- wget -qO- http://backend:8080/
```

From outside the mesh (should fail without proper identity):

```bash
kubectl run curl --rm -it --image=curlimages/curl -- curl -sS http://backend.mtls-demo:8080/
```

## 8. Grafana

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo

kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

## 9. Ingress / Gateway (optional)

Set `gateway_hostname` in terraform.tfvars and configure Route53 (or external DNS) to point to the Istio ingress LoadBalancer:

```bash
kubectl -n istio-system get svc istio-ingressgateway
```

## Troubleshooting

| Issue | Check |
|-------|-------|
| Argo apps OutOfSync | `kubectl -n argocd describe application <name>` |
| Istio pods not ready | cert-manager ClusterIssuer / istio-csr logs |
| Nodes not joining | EKS node group IAM, subnet tags |
| ALB not created | AWS Load Balancer Controller logs in `kube-system` |
