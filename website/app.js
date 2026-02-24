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

const inviteForm = document.getElementById("beta-invite-form");
const inviteNote = document.getElementById("beta-invite-note");

if (inviteForm) {
  const submitButton = inviteForm.querySelector('button[type="submit"]');
  const nextField = inviteForm.querySelector('input[name="_next"]');
  let isSubmitting = false;

  inviteForm.addEventListener("submit", () => {
    if (isSubmitting) return;
    isSubmitting = true;

    if (nextField && window.location?.origin) {
      const origin = window.location.origin;
      if (origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1")) {
        nextField.value = `${origin}/thank-you.html`;
      }
    }

    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Sending...";
    }

    if (inviteNote) {
      inviteNote.textContent =
        "Submitting... if the confirmation page does not load, email lorenjohnson@gmail.com.";
    }
  });
}
