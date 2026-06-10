// Customer-facing Web Push: site-wide device subscription (audience=client),
// opt-in by topic. Server endpoints live under /push/ via the :client_api
// pipeline, which keeps CSRF on — so writes send the x-csrf-token header.
//
// Used by: the vitrine soft-prompt, the /avisos config panel, and the order
// form (injects the device endpoint so confirm/cancel can notify this device).

const VAPID_URL = "/push/vapid-key";
const SUB_URL = "/push/subscribe";
const DISMISS_KEY = "sesh_lab.push_prompt_dismissed.v1";
const DEFAULT_TOPICS = ["order_status"];

function csrfToken() {
  return (
    document
      .querySelector("meta[name='csrf-token']")
      ?.getAttribute("content") || ""
  );
}

function pushSupported() {
  return "serviceWorker" in navigator && "PushManager" in window;
}

export async function getState() {
  if (!pushSupported()) {
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

// Endpoint of the device's current subscription, or null. Used to stamp orders.
export async function getEndpoint() {
  if (!pushSupported()) return null;
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  return sub ? sub.endpoint : null;
}

export async function enable(topics = DEFAULT_TOPICS) {
  if (!pushSupported()) throw new Error("Push não suportado neste navegador.");

  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("Permissão negada.");

  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();

  if (!sub) {
    const vapidKey = await fetchVapidKey();
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(vapidKey),
    });
  }

  await post(SUB_URL, "POST", {
    subscription: sub.toJSON(),
    topics,
    user_agent: navigator.userAgent,
  });
  return sub;
}

export async function disable() {
  if (!pushSupported()) return;
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;
  await post(SUB_URL, "DELETE", { endpoint: sub.endpoint });
  await sub.unsubscribe();
}

export async function updateTopics(topics) {
  const endpoint = await getEndpoint();
  if (!endpoint) return;
  await post(SUB_URL, "PATCH", { endpoint, topics });
}

async function fetchTopics() {
  const endpoint = await getEndpoint();
  if (!endpoint) return null;
  const url = `${SUB_URL}?endpoint=${encodeURIComponent(endpoint)}`;
  const res = await fetch(url, { credentials: "same-origin" });
  if (!res.ok) return null;
  const { topics } = await res.json();
  return Array.isArray(topics) ? topics : null;
}

// ── DOM bindings ────────────────────────────────────────────────────────────

// Soft pre-prompt: a dismissible bar injected into [data-push-prompt] on the
// vitrine. The real permission prompt only fires on the user's tap (browsers
// block/deny prompts not tied to a gesture). Dismissal is remembered.
export async function bindVitrinePrompt() {
  const mount = document.querySelector("[data-push-prompt]");
  if (!mount) return;
  if (localStorage.getItem(DISMISS_KEY) === "1") return;

  const state = await getState();
  if (!state.supported || state.subscribed || state.permission !== "default") {
    return;
  }

  const bar = document.createElement("div");
  bar.className = "alert alert--info push-prompt";

  const text = document.createElement("span");
  text.className = "text-base";
  text.textContent = "Quer ser avisado quando seu pedido for confirmado?";

  const actions = document.createElement("div");
  actions.className = "row gap-2 align-center";

  const yes = document.createElement("button");
  yes.type = "button";
  yes.className = "btn btn--primary btn--sm";
  yes.textContent = "Ativar avisos";
  yes.addEventListener("click", async () => {
    yes.disabled = true;
    try {
      await enable();
      mount.replaceChildren();
    } catch (e) {
      console.warn("[push] enable failed", e);
      yes.disabled = false;
    }
  });

  const no = document.createElement("button");
  no.type = "button";
  no.className = "btn btn--ghost btn--sm";
  no.textContent = "Agora não";
  no.addEventListener("click", () => {
    localStorage.setItem(DISMISS_KEY, "1");
    mount.replaceChildren();
  });

  actions.append(yes, no);
  bar.append(text, actions);
  mount.replaceChildren(bar);
}

// /avisos master toggle: a button with [data-client-push-toggle] whose label
// reflects subscription state.
export function bindAvisosToggle() {
  const btn = document.querySelector("[data-client-push-toggle]");
  if (!btn || btn.dataset.bound === "1") {
    if (btn) {
      refreshToggle(btn);
      syncTopicInputs();
    }
    return;
  }
  btn.dataset.bound = "1";
  refreshToggle(btn);
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    try {
      const state = await getState();
      if (state.subscribed) await disable();
      else await enable(selectedTopics());
    } catch (e) {
      console.warn("[push] toggle failed", e);
      alert(e.message || "Falha ao alterar avisos.");
    } finally {
      btn.disabled = false;
      refreshToggle(btn);
      syncTopicInputs();
    }
  });

  // Topic checkboxes ([data-topic="..."]) push their state when toggled.
  document.querySelectorAll("[data-topic]").forEach((box) => {
    box.addEventListener("change", async () => {
      const state = await getState();
      if (!state.subscribed) return;
      await updateTopics(selectedTopics());
    });
  });

  syncTopicInputs();
}

function selectedTopics() {
  return [...document.querySelectorAll("[data-topic]")]
    .filter((b) => b.checked)
    .map((b) => b.dataset.topic);
}

async function syncTopicInputs() {
  const state = await getState();
  const boxes = document.querySelectorAll("[data-topic]");
  boxes.forEach((b) => {
    b.disabled = !state.subscribed;
  });
  if (!state.subscribed) return;
  const topics = await fetchTopics();
  if (!topics) return;
  boxes.forEach((b) => {
    b.checked = topics.includes(b.dataset.topic);
  });
}

async function refreshToggle(btn) {
  const state = await getState();
  if (!state.supported) {
    btn.disabled = true;
    btn.textContent = "avisos não suportados neste navegador";
    return;
  }
  if (state.permission === "denied") {
    btn.disabled = true;
    btn.textContent = "avisos bloqueados no navegador";
    return;
  }
  btn.disabled = false;
  btn.dataset.state = state.subscribed ? "on" : "off";
  btn.textContent = state.subscribed ? "desativar avisos" : "ativar avisos";
}

// Order form: stamp the hidden client_endpoint field with this device's
// subscription endpoint (if any) so the order can be linked for status push.
export async function bindOrderEndpoint() {
  const field = document.querySelector("[data-client-endpoint]");
  if (!field) return;
  const endpoint = await getEndpoint();
  if (endpoint) field.value = endpoint;
}

// ── helpers ─────────────────────────────────────────────────────────────────

async function fetchVapidKey() {
  const res = await fetch(VAPID_URL, { credentials: "same-origin" });
  if (!res.ok) throw new Error(`Falha ao buscar chave VAPID (${res.status}).`);
  const { public_key } = await res.json();
  return public_key;
}

async function post(url, method, body) {
  const res = await fetch(url, {
    method,
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    body: JSON.stringify(body),
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`Falha (${res.status}).`);
  }
}

function urlBase64ToUint8Array(b64) {
  const padding = "=".repeat((4 - (b64.length % 4)) % 4);
  const base64 = (b64 + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const arr = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
  return arr;
}
