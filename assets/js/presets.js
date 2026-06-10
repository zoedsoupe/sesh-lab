export function bindPresets(root = document) {
  root.querySelectorAll("[data-presets]").forEach((group) => {
    if (group.dataset.bound) return;
    group.dataset.bound = "1";

    const inputName = group.dataset.presets;
    const input = document.querySelector(`[name="${inputName}"]`);
    if (!input) return;

    const syncActive = () => {
      const current = String(Number(input.value) || 0);
      group.querySelectorAll("[data-preset-value]").forEach((btn) => {
        btn.classList.toggle("is-active", btn.dataset.presetValue === current);
      });
    };

    group.querySelectorAll("[data-preset-value]").forEach((btn) => {
      btn.addEventListener("click", () => {
        input.value = btn.dataset.presetValue;
        input.dispatchEvent(new Event("input", { bubbles: true }));
        syncActive();
      });
    });

    input.addEventListener("input", syncActive);
    syncActive();
  });
}
