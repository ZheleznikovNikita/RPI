(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var form = document.querySelector("form[data-confirm-logout]");
    var dialog = document.getElementById("logout-confirmation");
    if (!form || !dialog) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (dialog.open) return;
      dialog.showModal();
    });

    dialog.querySelector("[data-cancel-logout]").addEventListener("click", function () {
      dialog.close();
    });

    dialog.querySelector("[data-confirm-logout-button]").addEventListener("click", function () {
      dialog.close();
      HTMLFormElement.prototype.submit.call(form);
    });
  });
})();
