// SSE consumer for vitrine stock updates. Replaces the prior meta-refresh:
// the server pushes `{id, stock}` whenever a product's stock moves (admin
// edit, order placed, order cancelled). We patch the matching card in place
// so open <details>, scroll position, and any user interaction survive.

let es = null;
let bound = false;

function patchCard(id, stock) {
  const card = document.querySelector(
    `[data-vitrine-stream] [data-product-id="${CSS.escape(id)}"]`,
  );
  if (!card) return;

  card.classList.toggle("is-sold-out", stock === 0);

  const badge = card.querySelector("[data-stock-badge]");
  if (!badge) return;

  const unit = card.dataset.unitLabel || "";

  if (stock === 0) {
    badge.className = "badge badge--expired";
    badge.textContent = "esgotado";
  } else {
    const word = stock === 1 ? "restante" : "restantes";
    badge.className = "text-xs text-muted";
    badge.textContent = `${stock} ${unit} ${word}`;
  }
  badge.dataset.stock = String(stock);
}

function open() {
  if (es) return;
  es = new EventSource("/vitrine/stream");
  es.onmessage = (e) => {
    try {
      const { id, stock } = JSON.parse(e.data);
      if (typeof id === "string" && Number.isInteger(stock)) {
        patchCard(id, stock);
      }
    } catch (_) {
      // ignore malformed payloads
    }
  };
  es.onerror = () => {
    // EventSource auto-reconnects; nothing to do.
  };
}

function close() {
  if (!es) return;
  es.close();
  es = null;
}

export function bindVitrineStream() {
  if (!document.querySelector("[data-vitrine-stream]")) {
    close();
    return;
  }
  if (!("EventSource" in window)) return;

  if (document.visibilityState === "visible") open();

  if (bound) return;
  bound = true;

  document.addEventListener("visibilitychange", () => {
    if (!document.querySelector("[data-vitrine-stream]")) {
      close();
      return;
    }
    if (document.visibilityState === "visible") {
      open();
    } else {
      close();
    }
  });
}
