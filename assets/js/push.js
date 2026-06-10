// Web Push subscribe / unsubscribe / status. Server endpoints live under
// /admin/push/. CSRF is not needed — those routes go through the `:admin_api`
// pipeline which doesn't include `:protect_from_forgery`.

const VAPID_URL = "/admin/push/vapid-key";
const SUB_URL = "/admin/push/subscribe";

export async function getPushState() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    return { supported: false, permission: "default", subscribed: false };
  }

  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  return {
    supported: true,
    permission: Notification.permission,
    subscribed: !!sub,
  };
}

export async function enablePush() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    throw new Error("Push não suportado neste navegador.");
  }

  const permission = await Notification.requestPermission();
  if (permission !== "granted") {
    throw new Error("Permissão negada.");
  }

  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();

  if (!sub) {
    const vapidKey = await fetchVapidKey();
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidKey),
    });
  }

  await postSubscription(sub);
  return sub;
}

export async function disablePush() {
  if (!("serviceWorker" in navigator)) return;

  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;

  await deleteSubscription(sub.endpoint);
  await sub.unsubscribe();
}

// Bind any button with `data-push-toggle` to the enable/disable flow and
// reflect current state in its label. Idempotent — safe to call on every
// `phx:page-loading-stop`.
export function bindPushToggle() {
  document.querySelectorAll("[data-push-toggle]").forEach((btn) => {
    if (btn.dataset.pushBound === "1") {
      updateLabel(btn);
      return;
    }
    btn.dataset.pushBound = "1";
    updateLabel(btn);
    btn.addEventListener("click", () => toggle(btn));
  });
}

async function toggle(btn) {
  btn.disabled = true;
  try {
    const state = await getPushState();
    if (state.subscribed) {
      await disablePush();
    } else {
      await enablePush();
    }
  } catch (e) {
    console.warn("[push] toggle failed", e);
    alert(e.message || "Falha ao alterar notificações.");
  } finally {
    btn.disabled = false;
    updateLabel(btn);
  }
}

async function updateLabel(btn) {
  const state = await getPushState();

  if (!state.supported) {
    btn.dataset.state = "unsupported";
    btn.disabled = true;
    btn.textContent = "push não suportado";
    return;
  }

  if (state.permission === "denied") {
    btn.dataset.state = "denied";
    btn.disabled = true;
    btn.textContent = "permissão bloqueada no navegador";
    return;
  }

  btn.dataset.state = state.subscribed ? "on" : "off";
  btn.disabled = false;
  btn.textContent = state.subscribed
    ? "notificações ativas"
    : "ativar notificações";
}

async function fetchVapidKey() {
  const res = await fetch(VAPID_URL, { credentials: "same-origin" });
  if (!res.ok) throw new Error(`Falha ao buscar chave VAPID (${res.status}).`);
  const { public_key } = await res.json();
  return public_key;
}

async function postSubscription(sub) {
  const res = await fetch(SUB_URL, {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      subscription: sub.toJSON(),
      user_agent: navigator.userAgent,
    }),
  });
  if (!res.ok)
    throw new Error(`Falha ao registrar subscription (${res.status}).`);
}

async function deleteSubscription(endpoint) {
  const res = await fetch(SUB_URL, {
    method: "DELETE",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ endpoint }),
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`Falha ao remover subscription (${res.status}).`);
  }
}

// applicationServerKey expects a Uint8Array of the raw 65-byte point.
function urlBase64ToUint8Array(b64) {
  const padding = "=".repeat((4 - (b64.length % 4)) % 4);
  const base64 = (b64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}
