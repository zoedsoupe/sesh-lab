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
