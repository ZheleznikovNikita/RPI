(function () {
  "use strict";
  document.addEventListener("DOMContentLoaded", function () {
    var menu = document.querySelector("[data-game-menu]");
    if (!menu) return;
    var trigger = menu.querySelector("summary");
    menu.addEventListener("toggle", function () {
      trigger.setAttribute("aria-label", menu.open ? "Закрыть игровое меню" : "Открыть игровое меню");
    });
    document.addEventListener("click", function (event) {
      if (menu.open && !menu.contains(event.target)) menu.open = false;
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && menu.open) {
        menu.open = false;
        trigger.focus();
      }
    });
    window.addEventListener("pagehide", function () { menu.open = false; });

    var finishForm = document.querySelector("form[data-confirm-finish]");
    var finishDialog = document.getElementById("finish-confirmation");
    if (!finishForm || !finishDialog) return;
    var confirmButton = finishDialog.querySelector("[data-confirm-finish-button]");
    finishForm.addEventListener("submit", function (event) {
      event.preventDefault();
      if (finishDialog.open) return;
      menu.open = false;
      finishDialog.showModal();
    });
    finishDialog.querySelector("[data-cancel-finish]").addEventListener("click", function () { finishDialog.close(); });
    finishDialog.addEventListener("click", function (event) {
      if (event.target !== finishDialog) return;
      var bounds = finishDialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) finishDialog.close();
    });
    finishDialog.addEventListener("close", function () { trigger.focus(); });
    confirmButton.addEventListener("click", function () {
      if (confirmButton.disabled) return;
      confirmButton.disabled = true;
      HTMLFormElement.prototype.submit.call(finishForm);
    });
    window.addEventListener("pageshow", function (event) {
      if (event.persisted) {
        confirmButton.disabled = false;
        if (finishDialog.open) finishDialog.close();
      }
    });
  });
})();
