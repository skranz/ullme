(function () {
  var records = [];

  function byId(id) {
    return document.getElementById(id);
  }

  function sendEvent(id, payload) {
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue(id, payload || {}, { priority: "event" });
    } else if (window.Shiny && Shiny.onInputChange) {
      Shiny.onInputChange(id, payload || {});
    }
  }

  function scalar(value) {
    if (Array.isArray(value)) return value.length ? value[0] : null;
    return value;
  }

  function number(value) {
    value = Number(scalar(value));
    return Number.isFinite(value) ? value : 0;
  }

  function option(value, label) {
    var item = document.createElement("option");
    item.value = value;
    item.textContent = label;
    return item;
  }

  function normalizeRecord(record) {
    function text(name) {
      var value = scalar(record && record[name]);
      return value == null ? "" : String(value);
    }
    var result = {
      day: text("day"),
      semester: text("semester"),
      courseid: text("courseid"),
      tutorid: text("tutorid"),
      model: text("model"),
      error: text("error")
    };
    [
      "requests", "replies", "errors", "sessions",
      "input_token_sum", "input_token_n",
      "output_token_sum", "output_token_n",
      "thinking_token_sum", "thinking_token_n",
      "ttf_ms_sum", "ttf_ms_n",
      "total_sec_sum", "total_sec_n"
    ].forEach(function (name) {
      result[name] = number(record && record[name]);
    });
    result.courseKey = result.semester + "::" + result.courseid;
    return result;
  }

  function formatNumber(value, digits) {
    value = Number(value);
    if (!Number.isFinite(value)) return "\u2014";
    return new Intl.NumberFormat(undefined, {
      maximumFractionDigits: digits == null
        ? (Math.abs(value) < 10 ? 1 : 0)
        : digits
    }).format(value);
  }

  function formatCompact(value) {
    value = Number(value);
    if (!Number.isFinite(value)) return "\u2014";
    try {
      return new Intl.NumberFormat(undefined, {
        notation: "compact",
        maximumFractionDigits: 1
      }).format(value);
    } catch (error) {
      return formatNumber(value, 0);
    }
  }

  function populateFilter(id, values, emptyLabel) {
    var select = byId(id);
    if (!select) return;
    var previous = select.value;
    select.innerHTML = "";
    select.appendChild(option("", emptyLabel));
    values.forEach(function (entry) {
      select.appendChild(option(entry.value, entry.label));
    });
    if (values.some(function (entry) {
      return entry.value === previous;
    })) {
      select.value = previous;
    }
  }

  function uniqueOptions(key, label) {
    var found = {};
    records.forEach(function (record) {
      var value = key(record);
      if (!value || found[value]) return;
      found[value] = label(record);
    });
    return Object.keys(found).sort(function (a, b) {
      return found[a].localeCompare(found[b]);
    }).map(function (value) {
      return { value: value, label: found[value] };
    });
  }

  function updateFilterOptions() {
    populateFilter(
      "ullme_usage_course_filter",
      uniqueOptions(
        function (record) { return record.courseKey; },
        function (record) {
          return record.semester + " \u00b7 " + record.courseid;
        }
      ),
      "All courses"
    );
    populateFilter(
      "ullme_usage_tutor_filter",
      uniqueOptions(
        function (record) { return record.tutorid; },
        function (record) { return record.tutorid; }
      ),
      "All Tutors"
    );
    populateFilter(
      "ullme_usage_model_filter",
      uniqueOptions(
        function (record) { return record.model; },
        function (record) { return record.model; }
      ),
      "All models"
    );
  }

  function filteredRecords() {
    var period = byId("ullme_usage_period");
    var course = byId("ullme_usage_course_filter");
    var tutor = byId("ullme_usage_tutor_filter");
    var model = byId("ullme_usage_model_filter");
    var days = period && period.value !== "all"
      ? Number(period.value)
      : null;
    var cutoff = days
      ? new Date(Date.now() - (days - 1) * 86400000)
      : null;
    if (cutoff) cutoff.setHours(0, 0, 0, 0);
    return records.filter(function (record) {
      if (course && course.value && record.courseKey !== course.value) {
        return false;
      }
      if (tutor && tutor.value && record.tutorid !== tutor.value) {
        return false;
      }
      if (model && model.value && record.model !== model.value) {
        return false;
      }
      if (cutoff && record.day === "unknown") return false;
      if (cutoff) {
        var date = new Date(record.day + "T00:00:00");
        if (!Number.isNaN(date.getTime()) && date < cutoff) return false;
      }
      return true;
    });
  }

  function totalsFor(selected) {
    var totals = {
      requests: 0,
      replies: 0,
      errors: 0,
      input_token_sum: 0,
      output_token_sum: 0,
      thinking_token_sum: 0,
      ttf_ms_sum: 0,
      ttf_ms_n: 0,
      total_sec_sum: 0,
      total_sec_n: 0
    };
    selected.forEach(function (record) {
      Object.keys(totals).forEach(function (name) {
        totals[name] += number(record[name]);
      });
    });
    return totals;
  }

  function renderCards(selected) {
    var container = byId("ullme_usage_cards");
    if (!container) return;
    var totals = totalsFor(selected);
    var errorRate = totals.requests
      ? 100 * totals.errors / totals.requests
      : 0;
    var ttf = totals.ttf_ms_n
      ? totals.ttf_ms_sum / totals.ttf_ms_n
      : null;
    var totalTime = totals.total_sec_n
      ? totals.total_sec_sum / totals.total_sec_n
      : null;
    var cards = [
      { label: "Requests", value: formatCompact(totals.requests) },
      { label: "Replies", value: formatCompact(totals.replies) },
      { label: "Error rate", value: formatNumber(errorRate, 1) + "%" },
      {
        label: "Input + output tokens",
        value: formatCompact(
          totals.input_token_sum + totals.output_token_sum
        )
      },
      {
        label: "Average TTF",
        value: ttf == null ? "\u2014" : formatNumber(ttf, 0) + " ms"
      },
      {
        label: "Average completion",
        value: totalTime == null
          ? "\u2014"
          : formatNumber(totalTime, 2) + " s"
      }
    ];
    container.innerHTML = "";
    cards.forEach(function (card) {
      var article = document.createElement("article");
      var value = document.createElement("strong");
      var label = document.createElement("span");
      article.className = "ullme-usage-metric";
      value.textContent = card.value;
      label.textContent = card.label;
      article.appendChild(value);
      article.appendChild(label);
      container.appendChild(article);
    });
  }

  function renderDaily(selected) {
    var container = byId("ullme_usage_daily_chart");
    if (!container) return;
    var grouped = {};
    selected.forEach(function (record) {
      if (!record.day || record.day === "unknown") return;
      grouped[record.day] = (grouped[record.day] || 0) + record.requests;
    });
    var days = Object.keys(grouped).sort();
    if (days.length > 60) days = days.slice(days.length - 60);
    var maximum = Math.max.apply(null, days.map(function (day) {
      return grouped[day];
    }).concat([1]));
    var labelEvery = Math.max(1, Math.ceil(days.length / 8));
    container.innerHTML = "";
    days.forEach(function (day, index) {
      var column = document.createElement("div");
      var bar = document.createElement("div");
      var label = document.createElement("span");
      column.className = "ullme-usage-day";
      column.title = day + ": " + grouped[day] + " requests";
      bar.className = "ullme-usage-day-bar";
      bar.style.height = Math.max(3, grouped[day] / maximum * 100) + "%";
      label.textContent = index % labelEvery === 0 ? day.slice(5) : "";
      column.appendChild(bar);
      column.appendChild(label);
      container.appendChild(column);
    });
  }

  function groupedValues(selected, key, label, errorsOnly) {
    var groups = {};
    selected.forEach(function (record) {
      var value = key(record);
      var amount = errorsOnly ? record.errors : record.requests;
      if (!value || !amount) return;
      if (!groups[value]) {
        groups[value] = { label: label(record), value: 0 };
      }
      groups[value].value += amount;
    });
    return Object.keys(groups).map(function (value) {
      return groups[value];
    }).sort(function (a, b) {
      return b.value - a.value || a.label.localeCompare(b.label);
    });
  }

  function renderBreakdown(id, values) {
    var container = byId(id);
    if (!container) return;
    values = values.slice(0, 8);
    var maximum = Math.max.apply(null, values.map(function (value) {
      return value.value;
    }).concat([1]));
    container.innerHTML = "";
    if (!values.length) {
      var empty = document.createElement("span");
      empty.className = "ullme-usage-breakdown-empty";
      empty.textContent = "No data";
      container.appendChild(empty);
      return;
    }
    values.forEach(function (value) {
      var row = document.createElement("div");
      var heading = document.createElement("div");
      var label = document.createElement("span");
      var count = document.createElement("strong");
      var track = document.createElement("div");
      var bar = document.createElement("div");
      row.className = "ullme-usage-breakdown-row";
      heading.className = "ullme-usage-breakdown-heading";
      label.textContent = value.label;
      label.title = value.label;
      count.textContent = formatCompact(value.value);
      track.className = "ullme-usage-breakdown-track";
      bar.className = "ullme-usage-breakdown-bar";
      bar.style.width = value.value / maximum * 100 + "%";
      heading.appendChild(label);
      heading.appendChild(count);
      track.appendChild(bar);
      row.appendChild(heading);
      row.appendChild(track);
      container.appendChild(row);
    });
  }

  function render() {
    var selected = filteredRecords();
    var empty = byId("ullme_usage_empty");
    var content = byId("ullme_usage_content");
    var hasData = selected.some(function (record) {
      return record.requests > 0;
    });
    if (empty) empty.style.display = hasData ? "none" : "";
    if (content) content.style.display = hasData ? "" : "none";
    renderCards(selected);
    if (!hasData) return;
    renderDaily(selected);
    renderBreakdown(
      "ullme_usage_course_chart",
      groupedValues(
        selected,
        function (record) { return record.courseKey; },
        function (record) {
          return record.semester + " \u00b7 " + record.courseid;
        },
        false
      )
    );
    renderBreakdown(
      "ullme_usage_model_chart",
      groupedValues(
        selected,
        function (record) { return record.model; },
        function (record) { return record.model; },
        false
      )
    );
    renderBreakdown(
      "ullme_usage_tutor_chart",
      groupedValues(
        selected,
        function (record) { return record.tutorid; },
        function (record) { return record.tutorid; },
        false
      )
    );
    renderBreakdown(
      "ullme_usage_error_chart",
      groupedValues(
        selected.filter(function (record) {
          return Boolean(record.error);
        }),
        function (record) { return record.error; },
        function (record) { return record.error; },
        true
      )
    );
  }

  function update(payload) {
    payload = payload || {};
    if (Array.isArray(payload.records)) {
      records = payload.records.map(normalizeRecord);
    }
    var status = byId("ullme_usage_status");
    var refresh = byId("ullme_usage_refresh_btn");
    var updating = payload.status === "updating";
    var updatedAt = scalar(payload.totals && payload.totals.updated_at);
    if (status) {
      status.textContent = payload.message ||
        (updatedAt ? "Updated " + updatedAt : "No aggregate created yet.");
      status.classList.toggle(
        "ullme-usage-status-warning",
        payload.status === "warning" || payload.status === "error"
      );
    }
    if (refresh) refresh.disabled = updating;
    updateFilterOptions();
    render();
  }

  function init() {
    var refresh = byId("ullme_usage_refresh_btn");
    if (refresh) {
      refresh.addEventListener("click", function () {
        sendEvent("ullme_usage_statistics_refresh_event", {});
      });
    }
    [
      "ullme_usage_period",
      "ullme_usage_course_filter",
      "ullme_usage_tutor_filter",
      "ullme_usage_model_filter"
    ].forEach(function (id) {
      var filter = byId(id);
      if (filter) filter.addEventListener("change", render);
    });
  }

  window.ullme = window.ullme || {};
  window.ullme.updateUsageStatistics = update;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
