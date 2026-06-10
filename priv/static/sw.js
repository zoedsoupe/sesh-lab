const CACHE = "sesh-shell-v3";
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
    // ── admin ──────────────────────────────────────────────────────────────
    case "new_order":
      return {
        title: `novo pedido — ${data.n || "cliente"}`,
        options: {
          body: `${data.q} ${data.q === 1 ? "ingresso" : "ingressos"} · r$ ${data.v}`,
          icon,
          badge,
          tag: `order-${data.id}`,
          data: { url: data.url || "/admin/" },
          requireInteraction: true,
        },
      };

    case "soldout":
      return {
        title: "lote esgotado",
        options: {
          body: data.name || "um lote esgotou",
          icon,
          badge,
          tag: `soldout-${data.name || ""}`,
          data: { url: data.url || "/admin/" },
        },
      };

    case "dj_application":
      return {
        title: `quer tocar — ${data.n || "alguém"}`,
        options: {
          body: "nova inscrição de DJ",
          icon,
          badge,
          data: { url: data.url || "/admin/tocar" },
        },
      };

    // ── client ─────────────────────────────────────────────────────────────
    case "order_status": {
      const map = {
        confirmed: {
          title: "ingressos confirmados",
          body: "toque pra ver seus QR codes",
        },
        cancelled: {
          title: "pedido cancelado",
          body: "toque pra ver os detalhes",
        },
        expired: { title: "pedido expirado", body: "o tempo do pix acabou" },
        pending: {
          title: "pedido recebido",
          body: "toque pra ver os detalhes",
        },
      };
      const m = map[data.s] || {
        title: "atualização do pedido",
        body: "toque pra ver",
      };
      return {
        title: m.title,
        options: {
          body: m.body,
          icon,
          badge,
          tag: `status-${data.id}`,
          data: { url: data.url || "/" },
          requireInteraction: data.s === "confirmed",
        },
      };
    }

    case "edition":
      return {
        title: data.title || "nova edição anunciada",
        options: {
          body: data.body || "",
          icon,
          badge,
          data: { url: data.url || "/" },
        },
      };

    case "coupon":
      return {
        title: data.title || "novo cupom",
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
        title: "SESH LAB.",
        options: {
          body: data.text || "",
          icon,
          badge,
          data: { url: "/" },
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
    // Admin is ALWAYS network — never cache /admin HTML. A cached 401 served on
    // the scanner mid-event is the worst failure mode at the door.
    if (url.pathname.startsWith("/admin")) {
      event.respondWith(fetch(req));
      return;
    }

    event.respondWith(
      fetch(req)
        .then((res) => {
          // Only cache successful responses — never a 401/404/500 shell.
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((cache) => cache.put(req, copy));
          }
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
