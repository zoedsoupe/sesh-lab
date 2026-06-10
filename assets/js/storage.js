const KEY = "sesh_lab.customer.v2";
const FIELDS = [
  "customer_name",
  "customer_instagram",
  "delivery_type",
  "address",
  "payment_method",
];

export function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || {};
  } catch {
    return {};
  }
}

export function save(data) {
  localStorage.setItem(KEY, JSON.stringify({ ...data, _v: 1 }));
}

export function clear() {
  localStorage.removeItem(KEY);
}

function fieldEl(form, name) {
  return form.querySelector(`[name="order[${name}]"]`);
}

export function bindForm(form) {
  if (!form) return;

  const data = load();
  const remember = form.querySelector("[data-remember]");
  const clearBtn = form.querySelector("[data-clear-storage]");

  if (Object.keys(data).length) {
    for (const f of FIELDS) {
      const el = fieldEl(form, f);
      if (el && data[f] != null && el.value === "") el.value = data[f];
    }
    if (remember) remember.checked = true;
  }

  form.addEventListener("submit", () => {
    if (remember?.checked) {
      const payload = {};
      for (const f of FIELDS) {
        const el = fieldEl(form, f);
        if (el) payload[f] = el.value;
      }
      save(payload);
    } else {
      clear();
    }
  });

  clearBtn?.addEventListener("click", () => {
    clear();
    for (const f of FIELDS) {
      const el = fieldEl(form, f);
      if (el) el.value = "";
    }
    if (remember) remember.checked = false;
  });
}
