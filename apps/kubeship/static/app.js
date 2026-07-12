const API = "/api/v1";
const STATUSES = ["picked_up", "in_transit", "delivered", "cancelled"];

const $ = (sel) => document.querySelector(sel);

const toast = (message, kind = "success") => {
  const el = $("#toast");
  el.textContent = message;
  el.className = `toast ${kind}`;
  clearTimeout(el._timer);
  el._timer = setTimeout(() => el.classList.add("hidden"), 4000);
};

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    headers: { "Content-Type": "application/json", ...options.headers },
    ...options,
  });
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const body = await res.json();
      detail = body.detail || JSON.stringify(body);
    } catch {
      /* ignore */
    }
    throw new Error(detail);
  }
  if (res.status === 204) return null;
  return res.json();
}

async function checkHealth() {
  const pill = $("#health-pill");
  try {
    const data = await fetch("/health").then((r) => r.json());
    pill.textContent = data.status === "ok" ? "API healthy" : "degraded";
    pill.className = `health ${data.status === "ok" ? "ok" : "err"}`;
  } catch {
    pill.textContent = "API unreachable";
    pill.className = "health err";
  }
}

async function loadCarriers() {
  const select = $("#carrier-select");
  try {
    const carriers = await api("/carriers");
    select.innerHTML = carriers
      .map((c) => `<option value="${c.id}">${c.name} (${c.region})</option>`)
      .join("");
    if (!carriers.length) {
      select.innerHTML = '<option value="local-courier">Local Courier</option>';
    }
  } catch (err) {
    select.innerHTML = '<option value="local-courier">Local Courier</option>';
    toast(`Could not load carriers: ${err.message}`, "error");
  }
}

function formatStatus(status) {
  return status.replaceAll("_", " ");
}

function formatTime(iso) {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

function renderShipment(shipment) {
  const panel = $("#shipment-panel");
  panel.classList.remove("hidden");

  $("#detail-tracking").textContent = shipment.tracking_number;
  const badge = $("#detail-status");
  badge.textContent = formatStatus(shipment.status);
  badge.className = `status-badge ${shipment.status}`;

  $("#detail-meta").innerHTML = `
    <div><dt>Shipment ID</dt><dd>${shipment.id}</dd></div>
    <div><dt>Carrier</dt><dd>${shipment.carrier}</dd></div>
    <div><dt>Origin</dt><dd>${shipment.origin.city}, ${shipment.origin.country}</dd></div>
    <div><dt>Destination</dt><dd>${shipment.destination.city}, ${shipment.destination.country}</dd></div>
    <div><dt>Weight</dt><dd>${shipment.weight_kg} kg</dd></div>
    <div><dt>Created</dt><dd>${formatTime(shipment.created_at)}</dd></div>
  `;

  const timeline = $("#detail-timeline");
  timeline.innerHTML = (shipment.status_history || [])
    .slice()
    .reverse()
    .map(
      (entry) =>
        `<li><strong>${formatStatus(entry.status)}</strong><time>${formatTime(entry.at)}</time></li>`
    )
    .join("");

  const actions = $("#status-actions");
  const next = STATUSES.filter((s) => s !== shipment.status);
  actions.innerHTML = next
    .map(
      (status) =>
        `<button type="button" class="btn" data-status="${status}" data-id="${shipment.id}">${formatStatus(status)}</button>`
    )
    .join("");

  actions.querySelectorAll("button").forEach((btn) => {
    btn.addEventListener("click", async () => {
      btn.disabled = true;
      try {
        const updated = await api(`/shipments/${btn.dataset.id}/status`, {
          method: "PATCH",
          body: JSON.stringify({ status: btn.dataset.status }),
        });
        renderShipment(updated);
        toast(`Status updated to ${formatStatus(updated.status)}`);
      } catch (err) {
        toast(err.message, "error");
      } finally {
        btn.disabled = false;
      }
    });
  });

  $("#track-input").value = shipment.tracking_number;
}

$("#create-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  const btn = form.querySelector('button[type="submit"]');
  btn.disabled = true;
  const data = new FormData(form);
  const payload = {
    origin: {
      city: data.get("origin_city"),
      country: String(data.get("origin_country")).toUpperCase(),
    },
    destination: {
      city: data.get("destination_city"),
      country: String(data.get("destination_country")).toUpperCase(),
    },
    carrier: data.get("carrier"),
    weight_kg: Number(data.get("weight_kg")),
  };
  try {
    const shipment = await api("/shipments", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    renderShipment(shipment);
    toast(`Created ${shipment.tracking_number}`);
    form.reset();
    form.querySelector('[name="origin_country"]').value = "CY";
  } catch (err) {
    toast(err.message, "error");
  } finally {
    btn.disabled = false;
  }
});

$("#track-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const code = $("#track-input").value.trim();
  const btn = e.target.querySelector('button[type="submit"]');
  btn.disabled = true;
  try {
    const shipment = await api(`/track/${encodeURIComponent(code)}`);
    renderShipment(shipment);
  } catch (err) {
    toast(err.message, "error");
  } finally {
    btn.disabled = false;
  }
});

checkHealth();
loadCarriers();
