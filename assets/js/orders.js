// Client-side order history. No backend: order ids are capability URLs
// (UUIDv4 at /compra/:id, which already renders status + PIX). We just
// remember the ids THIS device created so the customer can return to them
// without bookmarking. Mirrors the localStorage pattern in storage.js.

const KEY = "sesh_lab.orders.v1";
const MAX = 30;

function read() {
  try {
    const v = JSON.parse(localStorage.getItem(KEY));
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

function write(list) {
  localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX)));
}

// Record the order rendered on the current /compra/:id page. Idempotent —
// revisiting an order moves it to the top instead of duplicating.
export function bindOrderRecord() {
  const el = document.querySelector("[data-order-record]");
  const id = el?.dataset.id;
  if (!id) return;

  const entry = { id, label: el.dataset.label || id };
  const list = read().filter((o) => o.id !== id);
  list.unshift(entry);
  write(list);
}

// Populate [data-order-history] with links to each saved order, newest first.
// Shows an empty state when this device has no history.
export function renderOrderHistory() {
  const root = document.querySelector("[data-order-history]");
  if (!root) return;

  const list = read();
  root.replaceChildren();

  if (!list.length) {
    const p = document.createElement("p");
    p.className = "text-xs text-dim";
    p.textContent = "nenhum pedido neste aparelho ainda.";
    root.appendChild(p);
    return;
  }

  for (const o of list) {
    const a = document.createElement("a");
    a.href = `/compra/${encodeURIComponent(o.id)}`;
    a.className = "card row space-between align-center";

    const label = document.createElement("span");
    label.className = "text-sm text-mono";
    label.textContent = o.label || o.id;

    const cta = document.createElement("span");
    cta.className = "text-xs text-accent";
    cta.textContent = "ver →";

    a.append(label, cta);
    root.appendChild(a);
  }
}

const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

// Import an order this device never visited (e.g. a backfilled order whose
// link arrived by DM). On iOS the standalone PWA has its own localStorage,
// isolated from Safari — an external link can't reach it. The escape hatch:
// paste the /compra link HERE, inside the PWA, and we navigate to it in-scope
// so the show page's bindOrderRecord() writes to the PWA's own store.
export function bindOrderImport() {
  const form = document.querySelector("[data-order-import]");
  if (!form) return;

  const input = form.querySelector("input");

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const id = input.value.match(UUID)?.[0];
    if (!id) {
      input.setCustomValidity("link inválido — cole o /compra/... que você recebeu.");
      input.reportValidity();
      return;
    }
    // In-scope navigation: stays in the PWA context, so the order is recorded
    // in this store on arrival.
    location.assign(`/compra/${id}`);
  });

  input.addEventListener("input", () => input.setCustomValidity(""));
}
