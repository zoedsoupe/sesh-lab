const CACHE = "sesh-shell-v2";
const SHELL = [
  "/",
  "/manifest.webmanifest",
  "/images/mascara-192.png",
  "/images/mascara-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// ── Push notifications ──────────────────────────────────────────────────────
// Payload is a JSON object with shape `{ t, ... }` where `t` is the event
// type. Server: `SeshLab.Notifications`.

self.addEventListener("push", (event) => {
  const data = parsePayload(event);
  const { title, options } = renderNotification(data);

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url =
    (event.notification.data && event.notification.data.url) || "/admin/";

  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((wins) => {
        // Focus an open admin tab if one exists, else open a new one.
        for (const w of wins) {
          const u = new URL(w.url);
          if (u.pathname.startsWith("/admin")) {
            w.focus();
            return w.navigate ? w.navigate(url) : null;
          }
        }
        return self.clients.openWindow(url);
      }),
  );
});

function parsePayload(event) {
  if (!event.data) return { t: "unknown" };
  try {
    return event.data.json();
  } catch (_) {
    return { t: "unknown", text: event.data.text() };
  }
}

function renderNotification(data) {
  const icon = "/images/mascara-192.png";
  const badge = "/images/mascara-192.png";

  switch (data.t) {
    case "new_order":
      return {
        title: `novo pedido — ${data.n || "cliente"}`,
        options: {
          body: `${data.q} ${data.q === 1 ? "item" : "itens"} · r$ ${data.v}`,
          icon,
          badge,
          tag: `order-${data.id}`,
          data: { url: data.url || "/admin/" },
          requireInteraction: true,
        },
      };

    case "oos":
      return {
        title: "estoque zerado",
        options: {
          body: `${data.name || data.p} esgotou`,
          icon,
          badge,
          tag: `oos-${data.p}`,
          data: { url: data.url || "/admin/" },
        },
      };

    case "order_status": {
      const titles = {
        confirmed: "pedido confirmado",
        cancelled: "pedido cancelado",
        expired: "pedido expirado",
        pending: "pedido recebido",
      };
      return {
        title: titles[data.s] || "atualização do pedido",
        options: {
          body: "toque para ver os detalhes",
          icon,
          badge,
          tag: `status-${data.id}`,
          data: { url: data.url || "/" },
          requireInteraction: data.s === "confirmed",
        },
      };
    }

    case "promo":
      return {
        title: data.title || "novidade na sesh",
        options: {
          body: data.body || "",
          icon,
          badge,
          data: { url: data.url || "/" },
        },
      };

    case "coupon_expiring":
      return {
        title: "seu cupom expira amanhã",
        options: {
          body: `use ${data.code} antes que expire`,
          icon,
          badge,
          tag: `coupon-${data.code}`,
          data: { url: data.url || "/" },
        },
      };

    default:
      return {
        title: "sesh sesh",
        options: {
          body: data.text || "",
          icon,
          badge,
          data: { url: "/admin/" },
        },
      };
  }
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  const accept = req.headers.get("accept") || "";
  const isHTML = accept.includes("text/html");

  if (isHTML) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(req, copy));
          return res;
        })
        .catch(() =>
          caches.match(req).then((cached) => cached || caches.match("/")),
        ),
    );
    return;
  }

  // Assets (js/css): stale-while-revalidate — serve cached, refresh in bg.
  // Other static (images, fonts): cache-first.
  const isAsset = url.pathname.startsWith("/assets/");

  if (isAsset) {
    event.respondWith(
      caches.match(req).then((cached) => {
        const fresh = fetch(req).then((res) => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((cache) => cache.put(req, copy));
          }
          return res;
        });
        return cached || fresh;
      }),
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put(req, copy));
        }
        return res;
      });
    }),
  );
});
