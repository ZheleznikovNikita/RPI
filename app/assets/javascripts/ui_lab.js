(function () {
  var storageKey = "ai-text-rpg-ui-lab";
  var defaults = {
    "--milk": "#f3eadc",
    "--coffee": "#5f4535",
    "--espresso": "#2f211b",
    "--accent": "#b9824d",
    "--panel-alpha": "0.76",
    "--panel-blur": "18px",
    "--text-scale": "1"
  };

  var controls = [
    { label: "Фон страницы", property: "--milk", type: "color" },
    { label: "Текст и рамки", property: "--coffee", type: "color" },
    { label: "Тёмные кнопки", property: "--espresso", type: "color" },
    { label: "Акценты", property: "--accent", type: "color" },
    { label: "Прозрачность панели", property: "--panel-alpha", type: "range", min: "0.35", max: "0.95", step: "0.01" },
    { label: "Размытие панели", property: "--panel-blur", type: "range", min: "0", max: "30", step: "1", unit: "px" },
    { label: "Размер текста", property: "--text-scale", type: "range", min: "0.9", max: "1.15", step: "0.01" }
  ];

  function loadSettings() {
    try {
      return Object.assign({}, defaults, JSON.parse(localStorage.getItem(storageKey) || "{}"));
    } catch (_error) {
      return Object.assign({}, defaults);
    }
  }

  function saveSettings(settings) {
    localStorage.setItem(storageKey, JSON.stringify(settings));
  }

  function applySettings(settings) {
    Object.keys(settings).forEach(function (property) {
      document.documentElement.style.setProperty(property, settings[property]);
    });
  }

  function cleanValue(control, value) {
    if (control.unit && value.indexOf(control.unit) === -1) {
      return value + control.unit;
    }

    return value;
  }

  function rawValue(control, value) {
    return control.unit ? value.replace(control.unit, "") : value;
  }

  function buildPanel(settings) {
    var panel = document.createElement("aside");
    panel.className = "ui-lab";
    panel.innerHTML = [
      '<button class="ui-lab-toggle" type="button" aria-expanded="false">UI Lab</button>',
      '<div class="ui-lab-panel" aria-label="Редактор интерфейса в реальном времени">',
      "<strong>Настройка UI</strong>",
      '<div class="ui-lab-controls"></div>',
      '<button class="ui-lab-reset" type="button">Сбросить</button>',
      "</div>"
    ].join("");

    var toggle = panel.querySelector(".ui-lab-toggle");
    var controlsNode = panel.querySelector(".ui-lab-controls");

    controls.forEach(function (control) {
      var wrapper = document.createElement("label");
      var input = document.createElement("input");
      input.type = control.type;
      input.value = rawValue(control, settings[control.property]);
      if (control.min) input.min = control.min;
      if (control.max) input.max = control.max;
      if (control.step) input.step = control.step;

      wrapper.innerHTML = "<span>" + control.label + "</span>";
      wrapper.appendChild(input);
      controlsNode.appendChild(wrapper);

      input.addEventListener("input", function () {
        settings[control.property] = cleanValue(control, input.value);
        applySettings(settings);
        saveSettings(settings);
      });
    });

    toggle.addEventListener("click", function () {
      var isOpen = panel.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", String(isOpen));
    });

    panel.querySelector(".ui-lab-reset").addEventListener("click", function () {
      settings = Object.assign({}, defaults);
      saveSettings(settings);
      applySettings(settings);
      panel.remove();
      appendPanel(settings);
    });

    return panel;
  }

  function appendPanel(settings) {
    var container = document.querySelector("[data-ui-lab-container]") || document.body;
    container.appendChild(buildPanel(settings));
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (document.body.getAttribute("data-ui-lab") !== "enabled") {
      return;
    }

    var settings = loadSettings();
    applySettings(settings);
    appendPanel(settings);
  });
})();
