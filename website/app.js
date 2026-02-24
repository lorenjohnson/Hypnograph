const sections = document.querySelectorAll(".section-reveal");
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.15 }
);

sections.forEach((section) => observer.observe(section));

// Slider concept is intentionally paused for now.
const featureStage = document.querySelector("[data-feature-stage]");
if (featureStage) {
  const hotspots = Array.from(featureStage.querySelectorAll(".feature-hotspot"));
  const featureOverlay = featureStage.querySelector("[data-feature-overlay]");
  const featureOverlayTitle = featureOverlay?.querySelector(".feature-overlay-title");
  const featureOverlayBody = featureOverlay?.querySelector(".feature-overlay-body");

  const setActiveFeature = (featureName) => {
    let activeHotspot = null;
    hotspots.forEach((hotspot) => {
      const isActive = hotspot.dataset.feature === featureName;
      hotspot.classList.toggle("is-active", isActive);
      hotspot.setAttribute("aria-pressed", isActive ? "true" : "false");
      if (isActive) activeHotspot = hotspot;
    });

    if (!activeHotspot || !featureOverlay || !featureOverlayTitle || !featureOverlayBody) return;

    featureOverlayTitle.textContent = activeHotspot.dataset.title || "";
    featureOverlayBody.textContent = activeHotspot.dataset.body || "";

    const overlayX = activeHotspot.dataset.ox || "50";
    const overlayY = activeHotspot.dataset.oy || "50";
    const side = activeHotspot.dataset.side || "right";

    featureOverlay.style.setProperty("--overlay-x", `${overlayX}%`);
    featureOverlay.style.setProperty("--overlay-y", `${overlayY}%`);
    featureOverlay.classList.remove("is-left", "is-right", "is-center");
    featureOverlay.classList.add(`is-${side}`);
  };

  hotspots.forEach((hotspot) => {
    hotspot.addEventListener("click", () => {
      setActiveFeature(hotspot.dataset.feature || "");
    });
  });

  const initial = hotspots.find((node) => node.classList.contains("is-active")) || hotspots[0];
  if (initial) setActiveFeature(initial.dataset.feature || "");
}

const inviteForm = document.getElementById("beta-invite-form");
const inviteNote = document.getElementById("beta-invite-note");

if (inviteForm && inviteNote) {
  inviteForm.addEventListener("submit", (event) => {
    event.preventDefault();
    inviteNote.hidden = false;
  });
}
