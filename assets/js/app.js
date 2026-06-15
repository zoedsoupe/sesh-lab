// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
import { bindForm } from "./storage";
import { bindSteppers } from "./stepper";
import { bindCopyButtons } from "./copy";
import { bindPresets } from "./presets";
import { bindFormGate } from "./form_gate";
import { registerServiceWorker } from "./pwa";
import { bindPushToggle } from "./push";
import { bindOrderRecord, renderOrderHistory, bindOrderImport } from "./orders";
import {
  bindPostPurchasePrompt,
  bindAvisosToggle,
  bindOrderEndpoint,
} from "./client_push";
import { bindVitrineStream } from "./vitrine_stream";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/sesh_lab";
import topbar from "../vendor/topbar";

// Auto-dismiss flashes so the fixed-bottom toast never sits on top of a button
// (e.g. "publicar" on the edition form). LiveView pages use this hook, which
// also clears server-side flash state (via the phx-click lv:clear-flash) so a
// patched re-render doesn't bring it back. Resets the timer on each update so a
// fresh message gets its full lifetime. Dead views: see bindFlash() below.
const Hooks = {
  Flash: {
    mounted() {
      this.arm();
    },
    updated() {
      this.arm();
    },
    arm() {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.el.click(), 4500);
    },
    destroyed() {
      clearTimeout(this.timer);
    },
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  // window.SeshHooks is populated by separately-bundled entries (e.g.
  // scanner.js) loaded before this script on the pages that need them.
  hooks: { ...colocatedHooks, ...Hooks, ...(window.SeshHooks || {}) },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

function init() {
  const orderForm = document.getElementById("order-form");
  bindForm(orderForm);
  bindFormGate(orderForm);
  bindSteppers();
  bindPresets();
  bindCopyButtons();
  bindPushToggle();
  bindOrderRecord();
  renderOrderHistory();
  bindOrderImport();
  bindPostPurchasePrompt();
  bindAvisosToggle();
  bindOrderEndpoint();
  bindVitrineStream();
  bindFlash();
}

// Dead-view flashes (controller pages) get no LiveView hook — auto-hide them
// here. LiveView pages carry data-phx-session; skip those (the Flash hook owns
// them, and clears server state so they don't reappear).
function bindFlash() {
  if (document.querySelector("[data-phx-session]")) return;
  for (const el of document.querySelectorAll(".flash")) {
    if (el.dataset.armed) continue;
    el.dataset.armed = "1";
    const hide = () => el.classList.add("flash--hide");
    const t = setTimeout(hide, 4500);
    el.addEventListener("click", () => {
      clearTimeout(t);
      hide();
    });
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

window.addEventListener("phx:page-loading-stop", () => init());

registerServiceWorker();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
