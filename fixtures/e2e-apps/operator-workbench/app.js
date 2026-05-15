const routes = [...document.querySelectorAll("[data-route]")];
const links = [...document.querySelectorAll("[data-route-link]")];
const pulseOutput = document.querySelector("#pulse-output");
const queuedCount = document.querySelector("#queued-count");
const dialog = document.querySelector("#review-dialog");
const openReview = document.querySelector("#open-review");
const confirmReview = document.querySelector("#confirm-review");
const form = document.querySelector("#escalation-form");
const owner = document.querySelector("#owner");
const reason = document.querySelector("#reason");
const formMessage = document.querySelector("#form-message");

let frame = 0;
let reviewed = false;

function currentRoute() {
  const hash = window.location.hash.replace("#", "");
  return hash || "queue";
}

function renderRoute() {
  const active = currentRoute();
  routes.forEach((route) => {
    route.classList.toggle("is-active", route.dataset.route === active);
  });
  links.forEach((link) => {
    const isActive = link.dataset.routeLink === active;
    if (isActive) {
      link.setAttribute("aria-current", "page");
    } else {
      link.removeAttribute("aria-current");
    }
  });
}

function tick() {
  frame += 1;
  pulseOutput.textContent = `Frame ${frame}`;
  pulseOutput.style.backgroundColor = frame % 2 === 0 ? "#1f6feb" : "#8250df";
  queuedCount.textContent = String(reviewed ? 15 : 18 + (frame % 3));
}

openReview.addEventListener("click", () => {
  dialog.showModal();
});

confirmReview.addEventListener("click", () => {
  reviewed = true;
  queuedCount.textContent = "15";
});

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const missing = [];
  if (!owner.value.trim()) missing.push("owner");
  if (reason.value.trim().length < 12) missing.push("reason");

  if (missing.length > 0) {
    formMessage.classList.remove("is-success");
    formMessage.textContent = `Add ${missing.join(" and ")} before sending.`;
    return;
  }

  formMessage.classList.add("is-success");
  formMessage.textContent = "Escalation sent to release captain.";
});

document.querySelectorAll("[data-approve]").forEach((button) => {
  button.addEventListener("click", () => {
    button.textContent = "Approved";
    button.setAttribute("disabled", "");
  });
});

window.addEventListener("hashchange", renderRoute);
renderRoute();
tick();
setInterval(tick, 900);
