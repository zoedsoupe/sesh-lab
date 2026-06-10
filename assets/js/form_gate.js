export function bindFormGate(form) {
  if (!form) return;

  const submit = form.querySelector("button[type=submit]");
  if (!submit) return;

  const qtyInputs = form.querySelectorAll('input[name^="items["]');

  const hasItems = () => {
    for (const el of qtyInputs) {
      if (Number(el.value) > 0) return true;
    }
    return false;
  };

  const update = () => {
    const valid = form.checkValidity() && hasItems();
    submit.disabled = !valid;
    submit.classList.toggle("is-disabled", !valid);
  };

  form.addEventListener("input", update);
  form.addEventListener("change", update);
  update();
}
