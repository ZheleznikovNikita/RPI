(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var trigger = document.querySelector("[data-open-inventory]");
    var dialog = document.getElementById("inventory-dialog");
    if (!trigger || !dialog) return;

    trigger.addEventListener("click", function () {
      if (dialog.open) return;
      var menu = document.querySelector("[data-game-menu]");
      if (menu) menu.open = false;
      dialog.showModal();
      trigger.setAttribute("aria-expanded", "true");
    });

    dialog.querySelector("[data-close-inventory]").addEventListener("click", function () {
      dialog.close();
    });

    dialog.addEventListener("click", function (event) {
      if (event.target !== dialog) return;
      var bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) {
        dialog.close();
      }
    });

    dialog.addEventListener("close", function () {
      trigger.setAttribute("aria-expanded", "false");
    });
  });
})();
