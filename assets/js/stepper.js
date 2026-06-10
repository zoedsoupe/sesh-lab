export function bindSteppers(root = document) {
  root.querySelectorAll("[data-stepper]").forEach((el) => {
    if (el.dataset.bound) return;
    el.dataset.bound = "1";

    const input = el.querySelector("[data-stepper-input]");
    const decr = el.querySelector("[data-stepper-decr]");
    const incr = el.querySelector("[data-stepper-incr]");
    const rawMax = el.dataset.max || input.max || "";
    const max = rawMax === "" ? Infinity : Number(rawMax);

    const clamp = (n) => Math.min(Math.max(n, 0), max);

    decr.addEventListener("click", () => {
      input.value = clamp((Number(input.value) || 0) - 1);
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });

    incr.addEventListener("click", () => {
      input.value = clamp((Number(input.value) || 0) + 1);
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
  });
}
