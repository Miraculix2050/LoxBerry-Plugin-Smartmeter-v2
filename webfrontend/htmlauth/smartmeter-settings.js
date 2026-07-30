		var obis_job_id = "";
		var obis_job_serial = "";
		var obis_poll_timer = null;
		var obis_poll_failures = 0;
		var service_poll_timer = null;
		var service_poll_in_flight = false;
		var service_action_running = false;
		var service_action_timeout_timer = null;
		var service_action_feedback_timer = null;
		var last_service_snapshot = null;
		var ir_scan_running = false;
		var ir_scan_close_timer = null;
		var configuration_action_running = false;
		var configuration_action_elapsed_timer = null;
		var debug_log_tab = null;

		function service_ajax_url(action) {
			return "./index.cgi?ajax=1&ajaxaction=" + encodeURIComponent(action) + "&lang=" + encodeURIComponent(ui_language) + "&_=" + Date.now();
		}

		function append_csrf(data) {
			var token = document.getElementById("csrf_token");
			if (token) data.set("csrf_token", token.value);
			return data;
		}

		function update_recovery_controls() {
			var enabled = document.getElementById("recovery_ip_check_enabled").checked;
			var input = document.getElementById("recovery_allowed_ips");
			input.disabled = !enabled;
			document.getElementById("recovery_allowed_ips_row").classList.toggle("setting-disabled", !enabled);
		}

		function save_recovery_settings(operation) {
			if (operation === "rotate" && !window.confirm(obis_text("recovery_rotate_confirm_text"))) return;
			var feedback = document.getElementById("recovery_settings_feedback");
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "recovery-settings");
			data.append("lang", ui_language);
			data.append("recovery_operation", operation);
			data.append("recovery_enabled", document.getElementById("recovery_enabled").checked ? "1" : "0");
			data.append("recovery_ip_check_enabled", document.getElementById("recovery_ip_check_enabled").checked ? "1" : "0");
			data.append("recovery_allowed_ips", document.getElementById("recovery_allowed_ips").value);
			data.append("recovery_cooldown", document.getElementById("recovery_cooldown").value);
			append_csrf(data);
			feedback.textContent = "…";
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (response) {
					if (!response.ok) throw new Error(response.message || obis_text("recovery_request_failed_text"));
					feedback.textContent = response.message || "OK";
					if (response.token) {
						document.getElementById("recovery_plain_token").value = response.token;
						document.getElementById("recovery_token_output").hidden = false;
						document.getElementById("recovery_token_status").textContent = response.message;
					}
				})
				.catch(function (error) { feedback.textContent = error.message || obis_text("recovery_request_failed_text"); });
		}

		function copy_recovery_token() {
			var input = document.getElementById("recovery_plain_token");
			input.select();
			if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(input.value);
			else document.execCommand("copy");
		}

		function show_service_feedback(message, state, timeout) {
			var element = document.getElementById("service_action_feedback");
			if (service_action_feedback_timer) window.clearTimeout(service_action_feedback_timer);
			service_action_feedback_timer = null;
			if (!element) return;
			element.textContent = message;
			element.classList.remove("is-error", "is-running", "is-visible");
			if (!message) return;
			if (state == "error") element.classList.add("is-error");
			else if (state == "running") element.classList.add("is-running");
			element.classList.add("is-visible");
			if (timeout) {
				service_action_feedback_timer = window.setTimeout(function () {
					element.classList.remove("is-visible");
					service_action_feedback_timer = null;
				}, timeout);
			}
		}

		function show_action_success(message) {
			show_service_feedback(message, "success", 4000);
		}

		function clear_service_success() {
			show_service_feedback("", "", 0);
		}

		function set_service_button_state(id, visible, enabled, reason) {
			var button = $("#" + id);
			button.toggle(!!visible);
			button.prop("disabled", !enabled).toggleClass("is-disabled", !enabled);
			set_service_button_title(button, !enabled ? reason : "");
		}

		function set_service_button_title(button, reason) {
			var help = button.attr("data-help-title") || "";
			var title = help + (help && reason ? " " : "") + (reason || "");
			if (title) button.attr("title", title);
			else button.removeAttr("title");
		}

		function render_service_status(name, status) {
			if (!status) return;
			var element = $("#" + name + "_service_status");
			var service = name == "bridge" ? "smartmeter-v2-vzlogger-bridge" : "vzlogger";
			var installed = status.installed ? obis_text("service_installed_text") : obis_text("service_not_installed_text");
			var fallback = (status.state || "unknown") + " | PID: " + (status.pid || "-") + " | Service: " + service + " | " + installed;
			element.text(status.status_text || fallback);
			element.removeClass("service-status-idle service-status-ok service-status-warning service-status-error");
			element.addClass(status.status_class || "service-status-error");
		}

		function render_service_snapshot(response) {
			if (!response || !response.services) return;
			if (!last_service_snapshot) last_service_snapshot = {};
			last_service_snapshot.ok = response.ok;
			last_service_snapshot.services = response.services;
			if (response.applied) last_service_snapshot.applied = response.applied;
			if (response.config) last_service_snapshot.config = response.config;
			if (response.config) {
				expert_runtime_applied = !!response.config.expert_applied;
				if (expert_mode_active) {
					expert_mqtt_enabled = !!response.config.mqtt_enabled;
					expert_mqtt_timestamp = !!response.config.mqtt_timestamp;
				}
			}
			render_service_status("vzlogger", response.services.vzlogger);
			render_service_status("bridge", response.services.bridge);
			update_all_control_states();
		}

		function schedule_service_poll() {
			if (service_poll_timer) window.clearTimeout(service_poll_timer);
			service_poll_timer = null;
			if (!document.hidden && !service_action_running && !configuration_action_running) service_poll_timer = window.setTimeout(poll_service_status, 10000);
		}

		function poll_service_status() {
			if (document.hidden || service_action_running || configuration_action_running || service_poll_in_flight) {
				schedule_service_poll();
				return;
			}
			service_poll_in_flight = true;
			var status_url = "./service_status.cgi?details=" + (!last_service_snapshot ? "1" : "0") + "&lang=" + encodeURIComponent(ui_language) + "&_=" + Date.now();
			fetch(status_url, { credentials: "same-origin", cache: "no-store" })
				.then(function (response) {
					if (!response.ok) throw new Error("HTTP " + response.status);
					return response.json();
				})
				.then(render_service_snapshot)
				.catch(function () {})
				.then(function () {
					service_poll_in_flight = false;
					schedule_service_poll();
				});
		}

		function show_service_action_overlay(action) {
			var overlay = document.getElementById("service_action_overlay");
			if (!overlay) return;
			document.getElementById("service_action_spinner").style.display = "block";
			var title_id = "service_action_" + action.replace(/-/g, "_") + "_text";
			document.getElementById("service_action_title").textContent = obis_text(title_id);
			document.getElementById("service_action_overlay_message").textContent = obis_text("service_action_wait_text");
			document.getElementById("service_action_details").hidden = true;
			document.getElementById("service_action_details").textContent = "";
			document.getElementById("service_action_hide").hidden = false;
			document.getElementById("service_action_close").hidden = true;
			if (!overlay.open) overlay.showModal();
			document.getElementById("vzlogger_form").setAttribute("aria-busy", "true");
			overlay.focus();
			service_action_timeout_timer = window.setTimeout(function () {
				if (service_action_running) document.getElementById("service_action_overlay_message").textContent = obis_text("service_action_slow_text");
			}, 15000);
		}

		function hide_service_action_overlay() {
			var overlay = document.getElementById("service_action_overlay");
			if (overlay.open) overlay.close();
			if (service_action_running) {
				var title = document.getElementById("service_action_title").textContent.replace(/[.!?]\s*$/, "");
				show_service_feedback(title + ". " + obis_text("service_action_background_locked_text"), "running", 0);
			}
		}

		function close_service_action_overlay() {
			if (service_action_running) return;
			hide_service_action_overlay();
		}

		function finish_service_action_overlay(result, message) {
			if (service_action_timeout_timer) window.clearTimeout(service_action_timeout_timer);
			service_action_timeout_timer = null;
			document.getElementById("service_action_spinner").style.display = "none";
			document.getElementById("service_action_overlay_message").textContent = obis_text("service_action_" + result + "_text");
			var details = document.getElementById("service_action_details");
			details.textContent = message || "";
			details.hidden = !message;
			document.getElementById("service_action_hide").hidden = true;
			document.getElementById("service_action_close").hidden = false;
			document.getElementById("vzlogger_form").removeAttribute("aria-busy");
			if (result == "success") {
				hide_service_action_overlay();
				show_action_success(obis_text("service_action_success_text"));
			} else {
				clear_service_success();
				var overlay = document.getElementById("service_action_overlay");
				if (!overlay.open) overlay.showModal();
				overlay.focus();
			}
		}

		function run_service_action(action) {
			if (service_action_running) return;
			service_action_running = true;
			if (service_poll_timer) window.clearTimeout(service_poll_timer);
			service_poll_timer = null;
			update_all_control_states();
			clear_service_success();
			show_service_action_overlay(action);
			var action_ok = false;
			var action_result = "failed";
			var action_message = "";
			var needs_status_refresh = false;
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "service-action");
			data.append("lang", ui_language);
			data.append("service_action", action);
			if (/-vzlogger$/.test(action)) {
				data.append("vzlogger_enabled", smartmeterToggleValue("vzlogger_enabled"));
				data.append("vzlogger_service_debug", smartmeterToggleValue("vzlogger_service_debug"));
				data.append("vzlogger_loglevel", $("#vzlogger_loglevel").val());
			} else {
				data.append("vzlogger_enabled", smartmeterToggleValue("vzlogger_enabled"));
				data.append("bridge_enabled", smartmeterToggleValue("bridge_enabled"));
			}
			append_csrf(data);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) {
					if (!response.ok) throw new Error("HTTP " + response.status);
					return response.json();
				})
				.then(function (response) {
					action_ok = !!response.ok;
					action_result = !action_ok ? "failed" : (response.warning ? "warning" : "success");
					action_message = response.message || (response.ok ? "OK" : obis_text("service_action_failed_text"));
					render_service_snapshot(response);
					needs_status_refresh = !response.services;
				})
				.catch(function (error) {
					action_message = obis_text("service_action_failed_text") + ": " + error.message;
					action_result = "failed";
					needs_status_refresh = true;
				})
				.then(function () {
					service_action_running = false;
					update_all_control_states();
					finish_service_action_overlay(action_result, action_message);
					if (needs_status_refresh) poll_service_status();
					else schedule_service_poll();
				});
		}

		document.addEventListener("visibilitychange", function () {
			if (document.hidden) {
				if (service_poll_timer) window.clearTimeout(service_poll_timer);
				service_poll_timer = null;
			} else {
				poll_service_status();
			}
		});

		function obis_text(id) {
			var element = document.getElementById(id);
			return element ? element.textContent : "";
		}

		function configuration_action_text(action, suffix) {
			return obis_text("configuration_action_" + action.replace(/-/g, "_") + (suffix || "") + "_text");
		}

		function set_configuration_action_buttons(disabled) {
			["validate_config_button", "debug_log_button", "save_apply_button"].forEach(function (id) {
				var button = $("#" + id);
				button.prop("disabled", disabled).toggleClass("is-disabled", disabled);
			});
		}

		function show_configuration_action_overlay(action) {
			var overlay = document.getElementById("configuration_action_overlay");
			document.getElementById("configuration_action_spinner").style.display = "block";
			document.getElementById("configuration_action_title").textContent = configuration_action_text(action, "");
			document.getElementById("configuration_action_message").textContent = configuration_action_text(action, "_wait");
			document.getElementById("configuration_action_details").hidden = true;
			document.getElementById("configuration_action_details").textContent = "";
			var elapsed = document.getElementById("configuration_action_elapsed");
			var started = Date.now();
			function render_elapsed() {
				var seconds = Math.floor((Date.now() - started) / 1000);
				elapsed.textContent = obis_text("configuration_action_elapsed_text").replace("{seconds}", seconds);
				elapsed.hidden = false;
			}
			if (configuration_action_elapsed_timer) window.clearInterval(configuration_action_elapsed_timer);
			render_elapsed();
			configuration_action_elapsed_timer = window.setInterval(render_elapsed, 1000);
			document.getElementById("configuration_action_close").hidden = true;
			if (!overlay.open) overlay.showModal();
			document.getElementById("vzlogger_form").setAttribute("aria-busy", "true");
			overlay.focus();
		}

		function close_configuration_action_overlay() {
			if (configuration_action_running) return;
			var overlay = document.getElementById("configuration_action_overlay");
			if (overlay.open) overlay.close();
		}

		function finish_configuration_action_overlay(action, ok, message) {
			if (configuration_action_elapsed_timer) window.clearInterval(configuration_action_elapsed_timer);
			configuration_action_elapsed_timer = null;
			document.getElementById("configuration_action_spinner").style.display = "none";
			document.getElementById("configuration_action_message").textContent = obis_text(ok ? "configuration_action_success_text" : "configuration_action_failed_text");
			var details = document.getElementById("configuration_action_details");
			details.textContent = message || "";
			details.hidden = !message;
			document.getElementById("configuration_action_close").hidden = false;
			document.getElementById("vzlogger_form").removeAttribute("aria-busy");
			if (action == "apply" && ok) {
				close_configuration_action_overlay();
				show_action_success(obis_text("configuration_action_apply_success_text"));
			}
		}

		function escape_debug_tab_text(value) {
			return String(value || "").replace(/[&<>]/g, function (character) {
				return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[character];
			});
		}

		function open_debug_progress_tab() {
			if (debug_log_tab && !debug_log_tab.closed) {
				debug_log_tab.focus();
				return debug_log_tab;
			}
			var tab = window.open("", "_blank");
			if (!tab) return null;
			debug_log_tab = tab;
			var title = escape_debug_tab_text(obis_text("configuration_action_debug_tab_title_text"));
			var wait = escape_debug_tab_text(obis_text("configuration_action_debug_tab_wait_text"));
			var elapsedText = obis_text("configuration_action_debug_elapsed_text");
			var failedText = obis_text("configuration_action_failed_text");
			var timeoutText = obis_text("configuration_action_debug_timeout_text");
			var endpoint = new URL("./index.cgi?ajax=1&ajaxaction=debug-log&lang=" + encodeURIComponent(ui_language) + "&_=" + Date.now(), window.location.href).href;
			var csrfToken = (document.getElementById("csrf_token") || {}).value || "";
			var script = '(function(){var elapsed=0;var elapsedNode=document.getElementById("elapsed");var spinner=document.getElementById("spinner");var message=document.getElementById("message");var details=document.getElementById("details");var timer=setInterval(function(){elapsed++;elapsedNode.textContent=' + JSON.stringify(elapsedText) + '.replace("{seconds}",elapsed);},1000);var controller=window.AbortController?new AbortController():null;var browserTimeout=setTimeout(function(){if(controller)controller.abort();},52000);var data=new FormData();data.append("ajax","1");data.append("ajaxaction","debug-log");data.append("lang",' + JSON.stringify(ui_language) + ');data.append("csrf_token",' + JSON.stringify(csrfToken) + ');fetch(' + JSON.stringify(endpoint) + ',{method:"POST",body:data,credentials:"same-origin",cache:"no-store",signal:controller?controller.signal:undefined}).then(function(result){if(!result.ok)throw new Error("HTTP "+result.status);return result.json();}).then(function(response){if(!response.ok||!response.log_url)throw new Error(response.message||' + JSON.stringify(failedText) + ');try{if(window.opener)window.opener.debug_log_tab=null;}catch(ignore){}window.location.replace(response.log_url);}).catch(function(error){spinner.style.display="none";message.textContent=(error.name==="AbortError"?' + JSON.stringify(timeoutText) + ':' + JSON.stringify(failedText) + ');details.textContent=error.name==="AbortError"?"":(error.message||"");details.hidden=!details.textContent;}).then(function(){clearInterval(timer);clearTimeout(browserTimeout);});})();';
			tab.document.write('<!doctype html><html><head><meta charset="utf-8"><title>' + title + '</title><style>body{margin:0;background:#f3f5f7;color:#222;font:16px/1.5 system-ui,sans-serif;display:grid;min-height:100vh;place-items:center}.box{width:min(42rem,calc(100% - 3rem));text-align:center;padding:2rem}.spinner{width:42px;height:42px;margin:0 auto 1rem;border:4px solid #ccd3da;border-top-color:#2b6dad;border-radius:50%;animation:s .8s linear infinite}pre{padding:1rem;background:#fff;border:1px solid #ccd3da;text-align:left;white-space:pre-wrap}@keyframes s{to{transform:rotate(360deg)}}</style></head><body><main class="box"><div id="spinner" class="spinner"></div><h1>' + title + '</h1><p id="message">' + wait + '</p><p id="elapsed"></p><pre id="details" hidden></pre></main><script>' + script + '<\/script></body></html>');
			tab.document.close();
			return tab;
		}

		function mark_configuration_form_saved(response) {
			initial_vzlogger_enabled = smartmeterToggleValue("vzlogger_enabled");
			saved_vzlogger_enabled = initial_vzlogger_enabled;
			initial_bridge_enabled = smartmeterToggleValue("bridge_enabled");
			update_activation_dirty_hints();
			$("#vzlogger_mqttpass, #vzlogger_mqttkeypass").val("");
			$("#vzlogger_mqttpass_reset, #vzlogger_mqttkeypass_reset").prop("checked", false);
			if (response && response.action == "apply") {
				var removed_channel_state = false;
				document.querySelectorAll(".meter-remove-marker:not(:disabled)").forEach(function (marker) {
					var row = marker.closest("tr.meter-row");
					var serial = marker.value || (row && row.getAttribute("data-meter-serial")) || "";
					if (serial && channel_definitions.meters && Object.prototype.hasOwnProperty.call(channel_definitions.meters, serial)) {
						delete channel_definitions.meters[serial];
						removed_channel_state = true;
					}
					if (row) row.remove();
				});
				if (removed_channel_state) sync_channel_definitions();
				document.querySelectorAll(".meter-pending-badge, .obis-channel-new").forEach(function (marker) { marker.remove(); });
				document.querySelectorAll(".meter-template-note[id$='_template_unsaved']").forEach(function (note) { note.hidden = true; });
			}
			if (response && response.config && response.config.present) {
				$("#show_generated_config").removeClass("is-disabled").attr("aria-disabled", "false");
			}
		}

		function run_configuration_action(action) {
			if (configuration_action_running || service_action_running) return;
			if (action == "apply" && !expert_mode_active && expert_runtime_applied && !window.confirm(obis_text("expert_mode_overwrite_confirm_text"))) return;
			if (action == "debug-log") {
				if (!open_debug_progress_tab()) window.alert(obis_text("configuration_action_debug_popup_blocked_text"));
				return;
			}
			var form = document.getElementById("vzlogger_form");
			if (!form || (form.reportValidity && !form.reportValidity())) return;
			sync_channel_definitions();
			configuration_action_running = true;
			set_configuration_action_buttons(true);
			if (service_poll_timer) window.clearTimeout(service_poll_timer);
			service_poll_timer = null;
			show_configuration_action_overlay(action);
			var ok = false;
			var message = "";
			var data = new FormData(form);
			data.set("ajax", "1");
			data.set("ajaxaction", "form-action");
			data.set("lang", ui_language);
			data.set("submitaction", action);
			var controller = window.AbortController ? new AbortController() : null;
			var request_timeout = window.setTimeout(function () {
				if (controller) controller.abort();
			}, 70000);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store", signal: controller ? controller.signal : undefined })
				.then(function (result) {
					if (!result.ok) throw new Error("HTTP " + result.status);
					return result.json();
				})
				.then(function (response) {
					ok = !!response.ok;
					message = response.message || (ok ? obis_text("configuration_action_success_text") : obis_text("configuration_action_failed_text"));
					if (response.timed_out) message = obis_text("configuration_action_timeout_text") + (response.message ? "\n\n" + response.message : "");
					if (action == "apply" && response.ok) {
						mark_configuration_form_saved(response);
						if (response.ok && response.channel_indices) {
							runtime_channel_indices = response.channel_indices;
							document.getElementById("channel_indices_json").value = JSON.stringify(runtime_channel_indices);
							runtime_channel_topics = response.channel_topics || {};
							document.getElementById("channel_topics_json").value = JSON.stringify(runtime_channel_topics);
							document.querySelectorAll('.obis-editor').forEach(function(container){ render_channel_editor(container.id.replace(/_obis_channels$/,'')); });
						}
					}
					render_service_snapshot(response);
				})
				.catch(function (error) {
					message = error.name === "AbortError" ? obis_text("configuration_action_timeout_text") : obis_text("configuration_action_failed_text") + ": " + error.message;
				})
				.then(function () {
					window.clearTimeout(request_timeout);
					configuration_action_running = false;
					set_configuration_action_buttons(false);
					finish_configuration_action_overlay(action, ok, message);
					schedule_service_poll();
				});
		}

		function show_ir_head_scan() {
			var overlay = document.getElementById("ir_scan_overlay");
			ir_scan_running = true;
			if (ir_scan_close_timer) window.clearInterval(ir_scan_close_timer);
			ir_scan_close_timer = null;
			document.getElementById("ir_scan_spinner").style.display = "block";
			document.getElementById("ir_scan_title").textContent = obis_text("ir_scan_running_text");
			document.getElementById("ir_scan_message").textContent = obis_text("ir_scan_wait_text");
			document.getElementById("ir_scan_results").replaceChildren();
			document.getElementById("ir_scan_results").hidden = true;
			document.getElementById("ir_scan_staged_heading").hidden = true;
			document.getElementById("ir_scan_staged_results").replaceChildren();
			document.getElementById("ir_scan_staged_results").hidden = true;
			document.getElementById("ir_scan_countdown").hidden = true;
			document.getElementById("ir_scan_close").hidden = true;
			if (!overlay.open) overlay.showModal();
			document.getElementById("vzlogger_form").setAttribute("aria-busy", "true");
			overlay.focus();
		}

		function finish_ir_head_scan(status) {
			ir_scan_running = false;
			document.getElementById("ir_scan_spinner").style.display = "none";
			document.getElementById("ir_scan_title").textContent = obis_text("ir_scan_result_title_text");
			var message = status.result == "none" ? obis_text("ir_scan_none_text") :
				status.result == "no_new" ? obis_text("ir_scan_no_new_text") :
				status.result == "staged" ? obis_text("ir_scan_staged_found_text") : obis_text("ir_scan_found_text");
			document.getElementById("ir_scan_message").textContent = message;
			render_ir_head_list("ir_scan_results", status.heads || []);
			var staged = status.staged_heads || [];
			var staged_heading = document.getElementById("ir_scan_staged_heading");
			staged_heading.textContent = obis_text("ir_scan_staged_found_text");
			staged_heading.hidden = !(staged.length && (status.heads || []).length);
			render_ir_head_list("ir_scan_staged_results", staged);
			restore_staged_meter_panels(staged);
			document.getElementById("ir_scan_close").hidden = false;
			document.getElementById("vzlogger_form").removeAttribute("aria-busy");
			if (status.result == "no_new") start_ir_scan_countdown(3);
		}

		function render_ir_head_list(id, heads) {
			var list = document.getElementById(id);
			list.replaceChildren();
			heads.forEach(function (head) {
				var item = document.createElement("li");
				item.textContent = (head.name || head.serial) + ": " + head.path;
				list.appendChild(item);
			});
			list.hidden = !list.children.length;
		}

		function restore_staged_meter_panels(heads) {
			heads.forEach(function (head) {
				var panel = $(document.getElementById("meter_" + head.serial));
				if (!panel.length) return;
				panel.find(".meter-remove-marker").prop("disabled", true);
				panel.closest("tr").show();
			});
		}

		function synchronize_ir_head_panels() {
			return fetch("./index.cgi?form=vzlogger&_=" + Date.now(), { credentials: "same-origin", cache: "no-store" })
				.then(function (response) {
					if (!response.ok) throw new Error("HTTP " + response.status);
					return response.text();
				})
				.then(function (html) {
					var parsed = new DOMParser().parseFromString(html, "text/html");
					var parsed_channel_definitions = { meters: {} };
					try {
						parsed_channel_definitions = JSON.parse((parsed.getElementById("channel_definitions_json") || {}).value || "{}");
					} catch (error) {}
					parsed_channel_definitions.meters = parsed_channel_definitions.meters || {};
					var end = document.getElementById("meter_rows_end");
					if (!end) throw new Error("Meter insertion point not found.");
					parsed.querySelectorAll("tr.meter-row").forEach(function (source_row) {
						var source_panel = source_row.querySelector(".meter-panel");
						if (!source_panel || document.getElementById(source_panel.id)) return;
						var serial = source_row.getAttribute("data-meter-serial") || source_panel.id.substring("meter_".length);
						// A re-detected reader must use the freshly loaded server state. In
						// particular, never resurrect channels removed with the meter earlier
						// in this browser session.
						if (Object.prototype.hasOwnProperty.call(parsed_channel_definitions.meters, serial)) {
							channel_definitions.meters[serial] = parsed_channel_definitions.meters[serial];
						} else {
							delete channel_definitions.meters[serial];
						}
						var row = document.importNode(source_row, true);
						end.parentNode.insertBefore(row, end);
						initialize_meter_panel(row.querySelector(".meter-panel"), true);
					});
					sync_channel_definitions();
					update_all_control_states();
				});
		}

		function fail_ir_head_scan(message) {
			ir_scan_running = false;
			document.getElementById("ir_scan_spinner").style.display = "none";
			document.getElementById("ir_scan_title").textContent = obis_text("ir_scan_failed_title_text");
			document.getElementById("ir_scan_message").textContent = obis_text("ir_scan_failed_text") + " " + message;
			document.getElementById("ir_scan_results").hidden = true;
			document.getElementById("ir_scan_staged_heading").hidden = true;
			document.getElementById("ir_scan_staged_results").hidden = true;
			document.getElementById("ir_scan_countdown").hidden = true;
			document.getElementById("ir_scan_close").hidden = false;
			document.getElementById("vzlogger_form").removeAttribute("aria-busy");
		}

		function start_ir_scan_countdown(seconds) {
			var countdown = document.getElementById("ir_scan_countdown");
			function render() {
				countdown.textContent = obis_text("ir_scan_autoclose_text").replace("{seconds}", seconds);
				countdown.hidden = false;
			}
			render();
			ir_scan_close_timer = window.setInterval(function () {
				seconds--;
				if (seconds <= 0) {
					window.clearInterval(ir_scan_close_timer);
					ir_scan_close_timer = null;
					close_ir_head_scan();
					return;
				}
				render();
			}, 1000);
		}

		function close_ir_head_scan() {
			if (ir_scan_running) return;
			if (ir_scan_close_timer) window.clearInterval(ir_scan_close_timer);
			ir_scan_close_timer = null;
			var overlay = document.getElementById("ir_scan_overlay");
			if (overlay.open) overlay.close();
		}

		function start_ir_head_scan(event) {
			if (event) event.preventDefault();
			if (ir_scan_running || $("#rescan_ir_heads").attr("aria-disabled") == "true") return false;
			show_ir_head_scan();
			var controller = window.AbortController ? new AbortController() : null;
			var timed_out = false;
			var timeout = window.setTimeout(function () {
				timed_out = true;
				if (controller) controller.abort();
				else fail_ir_head_scan(obis_text("ir_scan_timeout_text"));
			}, 15000);
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "ir-scan");
			data.append("lang", ui_language);
			append_csrf(data);
			document.querySelectorAll(".meter-remove-marker:not(:disabled)").forEach(function (marker) {
				data.append("staged_removed", marker.value);
			});
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store", signal: controller ? controller.signal : undefined })
				.then(function (response) { return response.json(); })
				.then(function (status) {
					if (!status.ok) throw new Error(status.message || obis_text("ir_scan_failed_text"));
					return synchronize_ir_head_panels().then(function () { finish_ir_head_scan(status); });
				})
				.catch(function (error) {
					fail_ir_head_scan(timed_out ? obis_text("ir_scan_timeout_text") : (error.message || obis_text("ir_scan_failed_text")));
				})
				.then(function () { window.clearTimeout(timeout); });
			return false;
		}

		function show_obis_search_overlay() {
			var overlay = document.getElementById("obis_search_overlay");
			if (!overlay) return;
			document.getElementById("obis_search_spinner").style.display = "block";
			document.getElementById("obis_search_title").textContent = obis_text("obis_search_running_text");
			document.getElementById("obis_search_message").textContent = obis_text("obis_search_wait_text");
			document.getElementById("obis_search_cancel").disabled = false;
			if (!overlay.open) overlay.showModal();
			document.getElementById("vzlogger_form").setAttribute("aria-busy", "true");
			overlay.focus();
		}

		function reset_obis_search_overlay() {
			if (obis_poll_timer) window.clearTimeout(obis_poll_timer);
			obis_poll_timer = null;
			var overlay = document.getElementById("obis_search_overlay");
			if (overlay) {
				if (overlay.open) overlay.close();
			}
			var form = document.getElementById("vzlogger_form");
			if (form) form.removeAttribute("aria-busy");
			obis_job_id = "";
			obis_job_serial = "";
			obis_poll_failures = 0;
		}

		function obis_ajax_url(action) {
			if (action == "obis-status") return "./obis_status.cgi?lang=" + encodeURIComponent(ui_language) + "&_=" + Date.now();
			return "./index.cgi?ajax=1&ajaxaction=" + encodeURIComponent(action) + "&lang=" + encodeURIComponent(ui_language) + "&_=" + Date.now();
		}

		var channel_definitions = (function () {
			try { return JSON.parse(document.getElementById("channel_definitions_json").value || "{}"); }
			catch (error) { return { version: 1, meters: {} }; }
		})();
		var runtime_channel_indices = (function () {
			try { return JSON.parse(document.getElementById("channel_indices_json").value || "{}"); }
			catch (error) { return {}; }
		})();
		var runtime_channel_topics = (function () {
			try { return JSON.parse(document.getElementById("channel_topics_json").value || "{}"); }
			catch (error) { return {}; }
		})();
		var obis_catalog = (function () {
			try { return JSON.parse(document.getElementById("obis_catalog_json").value || "{}"); }
			catch (error) { return { entries: [], rules: [] }; }
		})();
		function html_text(value) {
			return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) { return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]; });
		}
		function channel_help_html(value) { return value ? '<small class="obis-channel-help">'+html_text(value)+'</small>' : ''; }
		function config_key_html(value) { return '<small class="config-key"><code>'+html_text(value)+'</code></small>'; }
		function channel_uuid() {
			if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
			return "xxxxxxxx-xxxx-4xxx-axxx-xxxxxxxxxxxx".replace(/x/g, function () { return Math.floor(Math.random() * 16).toString(16); });
		}
		function parse_obis_ui(value) {
			var match = String(value || "").trim().match(/^(?:(\d+)-(\d+):)?([A-Za-z0-9]+)\.(\d+)\.(\d+)(?:\*(\d+))?$/);
			if (!match) return null;
			var f = match[6] == null || match[6] == "255" ? null : Number(match[6]);
			if (f != null && (f < 0 || f > 254)) return null;
			return { a: match[1] == null ? null : Number(match[1]), b: match[2] == null ? null : Number(match[2]), c: /^\d+$/.test(match[3]) ? Number(match[3]) : match[3], d:Number(match[4]), e:Number(match[5]), f:f, base:(match[1] == null ? "" : match[1]+"-"+match[2]+":")+match[3]+"."+match[4]+"."+match[5] };
		}
		function full_obis(channel) { return channel.obis + (channel.storage == null || channel.storage === "" || String(channel.storage) === "255" ? "" : "*" + channel.storage); }
		function catalog_info(identifier) {
			var parsed = parse_obis_ui(identifier);
			if (!parsed) return { short: channel_labels.unknown, long: channel_labels.unknown, unit:"", recommended_aggmode:"none", output_name:"Unknown" };
			var full = parsed.base + (parsed.f == null ? "" : "*" + parsed.f);
			var entry = (obis_catalog.entries || []).find(function (item) { return item.code === full; }) || (obis_catalog.entries || []).find(function (item) { return item.code === parsed.base; });
			if (!entry) entry = (obis_catalog.rules || []).slice().sort(function(a,b){return (a.priority||9999)-(b.priority||9999);}).find(function (item) { return Object.keys(item.match || {}).every(function(group){ var wanted=item.match[group], actual=parsed[group]; return Array.isArray(wanted) ? wanted.map(String).indexOf(String(actual))>=0 : String(wanted)===String(actual); }); });
			var lang = (document.documentElement.lang && document.documentElement.lang.toLowerCase().indexOf("de") === 0) || channel_labels.active === "Aktiv" ? "de" : "en";
			var groups=(lang==='de'?' Gruppen A (Medium)=':' Groups A (medium)=')+(parsed.a==null?(lang==='de'?'nicht angegeben':'not specified'):parsed.a)+', B ('+(lang==='de'?'Kanal':'channel')+')='+(parsed.b==null?(lang==='de'?'nicht angegeben':'not specified'):parsed.b)+', C ('+(lang==='de'?'Messgröße':'quantity')+')='+parsed.c+', D ('+(lang==='de'?'Verarbeitung':'processing')+')='+parsed.d+', E ('+(lang==='de'?'Tarif/Ausprägung':'tariff/variant')+')='+parsed.e+', F ('+(lang==='de'?'Speicher':'storage')+')='+(parsed.f==null?(lang==='de'?'nicht angegeben':'not specified'):parsed.f)+'.';
			if (!entry) return { short:channel_labels.unknown, long:channel_labels.unknown+groups, unit:"", recommended_aggmode:"none", output_name:"Unknown" };
			return { short:(entry.short||{})[lang] || (entry.short||{}).en || parsed.base, long:((entry.long||{})[lang] || (entry.long||{}).en || "")+groups, unit:entry.unit||"", recommended_aggmode:entry.recommended_aggmode||"none", warning:((entry.limitations||{})[lang]||""), output_name:entry.output_name||((entry.short||{}).en||"") };
		}
		function default_output_key_ui(parsed, info) {
			var name=String((info||{}).output_name||(info||{}).short||"Unknown").replace(/\s+/g,"_").replace(/[^A-Za-z0-9_]+/g,"_").replace(/^_+|_+$/g,"")||"Value";
			var shortObis=parsed.c+"."+parsed.d+"."+parsed.e+(parsed.f==null?"":"*"+parsed.f), suffix="_OBIS_"+shortObis, available=64-suffix.length; if(available<1)return ("Value"+suffix).substring(0,64);
			if(name.length>available) name=name.substring(0,available).replace(/_+$/g,"");
			return name+suffix;
		}
		function unique_output_key_ui(serial, key) {
			var used={}; (channel_definitions.meters[serial]||[]).forEach(function(ch){var existing=((ch.plugin_output||{}).key||"").toLowerCase();if(existing)used[existing]=true;});
			var candidate=key, number=2; while(used[candidate.toLowerCase()]){var suffix="_"+number++;candidate=key.substring(0,64-suffix.length)+suffix;} return candidate;
		}
		function validate_output_key_input(input) {
			if(!input||input.disabled||input.value===""){if(input)input.setCustomValidity("");return;}
			input.setCustomValidity(/^[A-Za-z0-9 _#|()\[\]\/\'%$!.*-]{1,64}$/.test(input.value)?"":channel_labels.outputKeyFormat);
		}
		function channel_details_storage_key(serial, uuid) {
			return SmartMeterVZLoggerUi.storageKey("channel-details", serial + ":" + uuid);
		}
		function channel_details_open(serial, uuid, fallback) {
			if (!uuid) return !!fallback;
			return SmartMeterVZLoggerUi.readOpen("channel-details", serial + ":" + uuid, fallback);
		}
		function persist_channel_details(serial, uuid, open) {
			if (!uuid) return;
			SmartMeterVZLoggerUi.writeOpen("channel-details", serial + ":" + uuid, open);
		}
		var channel_definitions_sync_timer = null;
		function sync_channel_definitions() {
			if (channel_definitions_sync_timer) window.clearTimeout(channel_definitions_sync_timer);
			channel_definitions_sync_timer = null;
			document.getElementById("channel_definitions_json").value = JSON.stringify(channel_definitions);
		}
		function schedule_channel_definitions_sync() {
			if (channel_definitions_sync_timer) window.clearTimeout(channel_definitions_sync_timer);
			channel_definitions_sync_timer = window.setTimeout(sync_channel_definitions, 200);
		}
		function api_option_fields(api, options) {
			var fields = [];
			if (api === "volkszaehler") fields = [["middleware","Middleware",true],["timeout","Timeout",false]];
			if (api === "influxdb") fields = [["version","Version (1 / 2)"],["host","Host",true],["database","Database / Bucket"],["organization","Organization"],["measurement_name","Measurement"],["tags","Tags (JSON)"],["token","Token"],["username","Username"],["password","Password"],["timeout","Timeout"],["max_batch_inserts","Batch"],["max_buffer_size","Buffer"],["send_uuid","Send UUID",false,"checkbox"],["ssl_verifypeer","TLS verify peer",false,"checkbox"]];
			if (api === "mysmartgrid") fields = [["middleware","Middleware",true],["secretKey","Secret key",true],["device","Device",true],["type","Type",true],["interval","Interval"],["scaler","Scaler"],["timeout","Timeout"],["name",channel_labels.registrationName]];
			return fields.map(function(field){ var value=options[field[0]]; if(value==null && (field[0]==='send_uuid'||field[0]==='ssl_verifypeer')) value=true; var type=field[3]||((/password|token|secretKey/.test(field[0]))?"password":"text"); return '<div class="obis-channel-field lb-form-field"><label>'+html_text(field[1])+(field[2]?' *':'')+'</label>'+config_key_html('meters[].channels[].'+field[0])+'<input class="'+(type==='checkbox'?'ch-option-checkbox':'lb-input')+'" data-option="'+field[0]+'" type="'+type+'" '+(field[2]?'required ':'')+(type==='checkbox'?(value?'checked':''):'value="'+html_text(value==null?"":(typeof value==='object'?JSON.stringify(value):value))+'"')+'>'+channel_help_html(api_field_help[field[0]])+'</div>'; }).join("");
		}
		function render_channel_editor(serial) {
			channel_definitions.meters = channel_definitions.meters || {};
			var channels = channel_definitions.meters[serial] || (channel_definitions.meters[serial] = []);
			var container = document.getElementById(serial + "_obis_channels"); if (!container) return;
			var open_by_uuid = {};
			container.querySelectorAll('.obis-channel-card').forEach(function(card) { var existing=channels[Number(card.getAttribute('data-index'))], details=card.querySelector('details.obis-channel-details'); if(existing && existing.uuid && details && details.open) open_by_uuid[existing.uuid]=true; });
			container.innerHTML = "";
			channels.forEach(function(channel, index) {
				container.appendChild(create_channel_card(serial,index,!!open_by_uuid[channel.uuid]));
			});
			initialize_channel_editor_events(container,serial);
			var empty=document.getElementById(serial+'_obis_empty'); if(empty) empty.hidden=channels.length>0; sync_channel_definitions();
		}
		function create_channel_card(serial,index,was_open) {
			var channel=channel_definitions.meters[serial][index], container=document.getElementById(serial+'_obis_channels');
			channel.api_options=channel.api_options||{volkszaehler:{},influxdb:{},mysmartgrid:{}}; channel.plugin_output=channel.plugin_output||{enabled:true,key:""}; if(channel.storage==null||channel.storage===""||String(channel.storage)==="255") channel.storage=null;
			var info=catalog_info(full_obis(channel)),title=channel.display_name||info.short,api=channel.api||'null',source=channel.origin==='manual'?channel_labels.originManual:channel_labels.originFound;
			var effectiveTopic=runtime_channel_topics[String(channel.uuid||'').toLowerCase()]||channel_labels.mqttPathUnavailable;
			var status=channel_labels.source+': '+source+' · '+channel_labels.apiTarget+': '+(api==='null'?channel_labels.apiNone:api)+' · '+channel_labels.bridgeOutput+': '+(channel.plugin_output.enabled?channel_labels.enabledState:channel_labels.disabledState)+' · '+channel_labels.mqttPath+': '+effectiveTopic;
			var applied=runtime_channel_indices[String(channel.uuid||'').toLowerCase()],assigned=Number.isInteger(applied),number=assigned?channel_labels.channelNumber.replace('{number}',applied):channel_labels.channelUnassigned;
			var open=channel_details_open(serial,channel.uuid,was_open),card=document.createElement('div'); card.className='obis-channel-card'; card.dataset.index=index;
			card.innerHTML='<div class="obis-channel-summary"><input class="ch-enabled" type="checkbox" '+(channel.enabled?'checked':'')+' title="'+html_text(channel_labels.active)+'"><span class="obis-channel-number" title="'+html_text(assigned?channel_labels.channelNumberHelp:channel_labels.channelUnassignedHelp)+'">'+html_text(number)+'</span><code>'+html_text(full_obis(channel))+'</code><span title="'+html_text(info.long+(info.unit?' ['+info.unit+']':''))+'">'+html_text(title)+'</span><span class="obis-channel-status">'+html_text(status)+'</span></div><details class="obis-channel-details" '+(open?'open':'')+'><summary>'+html_text(channel_labels.details)+'<span class="obis-channel-uuid">· UUID: '+html_text(channel.uuid||'–')+'</span></summary><div class="obis-channel-grid" data-lazy="1"></div></details>';
			if(open) render_channel_details(serial,index,card);
			return card;
		}
		function render_channel_details(serial,index,card) {
			var grid=card.querySelector('.obis-channel-grid'); if(!grid||grid.dataset.rendered==='1') return;
			var channel=channel_definitions.meters[serial][index],container=document.getElementById(serial+'_obis_channels'),protocol=container.getAttribute('data-protocol')||'',aggtime=Number((document.getElementById(serial+'_aggtime')||{}).value||0),api=channel.api||'null',options=channel.api_options[api]||{},info=catalog_info(full_obis(channel));
			var remove=channel.origin==='manual'?'<div class="obis-channel-remove"><button class="ch-remove obis-channel-remove-button lb-btn lb-compact" type="button"><i class="pi pi-trash" aria-hidden="true"></i>'+html_text(channel_labels.remove)+'</button>'+channel_help_html(channel_labels.removeHelp)+'</div>':'';
			grid.innerHTML='<div class="obis-channel-info"><strong>'+html_text(info.short)+'</strong>'+(info.unit?' · '+html_text(info.unit):'')+'<br>'+html_text(info.long)+(info.warning?'<br>'+html_text(info.warning):'')+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.identifier)+'</label>'+config_key_html('meters[].channels[].identifier')+'<input class="ch-obis lb-input" required value="'+html_text(channel.obis)+'">'+channel_help_html(channel_help.identifier)+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.storage)+'</label>'+config_key_html('meters[].channels[].identifier')+'<div class="obis-storage-control"><input class="ch-storage obis-number-spinner lb-input" type="number" min="0" max="254" step="1" inputmode="numeric" '+(protocol==='oms'?'disabled title="'+html_text(channel_labels.storageOms)+'"':'')+' value="'+html_text(channel.storage==null?'':channel.storage)+'"><button class="ch-storage-clear obis-storage-clear lb-btn '+(channel.storage==null?'is-active':'')+'" type="button" aria-pressed="'+(channel.storage==null?'true':'false')+'" '+(protocol==='oms'?'disabled ':'')+'title="'+html_text(channel_labels.storageClear)+'">'+html_text(channel_labels.storageClear)+'</button></div>'+channel_help_html(protocol==='oms'?channel_labels.storageOms:channel_help.storage)+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.display)+'</label><small class="config-key config-key-spacer" aria-hidden="true">&nbsp;</small><input class="ch-display lb-input" value="'+html_text(channel.display_name||'')+'">'+channel_help_html(channel_help.display)+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.api)+'</label>'+config_key_html('meters[].channels[].api')+'<select class="ch-api lb-select"><option value="null">'+html_text(channel_labels.apiNoneOption)+'</option><option value="volkszaehler">volkszaehler</option><option value="influxdb">influxdb</option><option value="mysmartgrid">mysmartgrid</option></select>'+channel_help_html(channel_help.api)+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.aggregation)+'</label>'+config_key_html('meters[].channels[].aggmode')+'<select class="ch-agg lb-select" '+(aggtime>0?'':'disabled')+'><option value="none">none</option><option value="avg">avg</option><option value="max">max</option><option value="sum">sum</option></select>'+channel_help_html(channel_help.aggregation)+'</div><div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.duplicates)+'</label>'+config_key_html('meters[].channels[].duplicates')+'<input class="ch-duplicates lb-input" type="number" min="0" '+((api==='volkszaehler'||api==='influxdb')?'':'disabled')+' value="'+html_text(channel.duplicates||0)+'">'+channel_help_html(channel_help.duplicates)+'</div><div class="obis-api-fields"><strong>'+html_text(channel_labels.apiOptions)+'</strong>'+api_option_fields(api,options)+'</div><div class="obis-output-fields"><label><input class="ch-output" type="checkbox" '+(channel.plugin_output.enabled?'checked':'')+'> '+html_text(channel_labels.output)+'</label>'+channel_help_html(channel_help.output)+'<div class="obis-channel-field lb-form-field"><label>'+html_text(channel_labels.outputKey)+'</label><input class="ch-output-key lb-input" maxlength="64" title="'+html_text(channel_labels.outputKeyFormat)+'" '+(channel.plugin_output.enabled?'required':'disabled')+' value="'+html_text(channel.plugin_output.key||'')+'">'+channel_help_html(channel_help.outputKey)+'</div></div>'+remove;
			grid.dataset.rendered='1'; delete grid.dataset.lazy; grid.querySelector('select.ch-api').value=api; grid.querySelector('select.ch-agg').value=aggtime>0?(channel.aggmode||'none'):'none'; validate_output_key_input(grid.querySelector('input.ch-output-key'));
		}
		function replace_channel_card(serial,index,card) { var details=card.querySelector('details'); card.replaceWith(create_channel_card(serial,index,details&&details.open)); update_meter_enabled(serial); }
		function initialize_channel_editor_events(container,serial) {
			if(container.dataset.eventsReady==='1') return; container.dataset.eventsReady='1';
			container.addEventListener('toggle',function(event){if(!event.target.matches('details.obis-channel-details'))return;var card=event.target.closest('.obis-channel-card'),index=Number(card.dataset.index),channel=channel_definitions.meters[serial][index];if(event.target.open){render_channel_details(serial,index,card);update_meter_enabled(serial);}persist_channel_details(serial,channel.uuid,event.target.open);},true);
			container.addEventListener('click',function(event){var card=event.target.closest('.obis-channel-card');if(!card)return;var index=Number(card.dataset.index);if(event.target.closest('.ch-remove')){remove_manual_channel(serial,index,(card.querySelector('.obis-channel-number')||{}).textContent||'');return;}var clear=event.target.closest('.ch-storage-clear');if(clear){var input=card.querySelector('.ch-storage');input.value='';update_channel_card(serial,index,card,container.getAttribute('data-protocol')||'',Number((document.getElementById(serial+'_aggtime')||{}).value||0));replace_channel_card(serial,index,card);}});
			container.addEventListener('change',function(event){var card=event.target.closest('.obis-channel-card');if(!card)return;var index=Number(card.dataset.index),channel=channel_definitions.meters[serial][index];if(event.target.classList.contains('ch-enabled')){channel.enabled=event.target.checked;sync_channel_definitions();update_meter_enabled(serial);return;}update_channel_card(serial,index,card,container.getAttribute('data-protocol')||'',Number((document.getElementById(serial+'_aggtime')||{}).value||0));if(['ch-api','ch-output','ch-obis','ch-storage','ch-display'].some(function(name){return event.target.classList.contains(name);}))replace_channel_card(serial,index,card);});
			container.addEventListener('input',function(event){var card=event.target.closest('.obis-channel-card');if(!card||!card.querySelector('[data-rendered="1"]'))return;var index=Number(card.dataset.index);update_channel_card(serial,index,card,container.getAttribute('data-protocol')||'',Number((document.getElementById(serial+'_aggtime')||{}).value||0));if(event.target.classList.contains('ch-output-key'))validate_output_key_input(event.target);});
		}
		function update_channel_card(serial,index,card,protocol,aggtime) {
			var ch=channel_definitions.meters[serial][index], parsed=parse_obis_ui(card.querySelector('input.ch-obis').value); if(parsed) ch.obis=parsed.base;
			ch.enabled=card.querySelector('input.ch-enabled').checked; ch.storage=protocol==='oms'?null:(card.querySelector('input.ch-storage').value===''?null:Number(card.querySelector('input.ch-storage').value)); ch.display_name=card.querySelector('input.ch-display').value; ch.api=card.querySelector('select.ch-api').value; ch.aggmode=aggtime>0?card.querySelector('select.ch-agg').value:'none'; ch.duplicates=Number(card.querySelector('input.ch-duplicates').value||0); ch.plugin_output.enabled=card.querySelector('input.ch-output').checked; ch.plugin_output.key=card.querySelector('input.ch-output-key').value;
			var opts=ch.api_options[ch.api]||(ch.api_options[ch.api]={}); card.querySelectorAll('[data-option]').forEach(function(input){ var value=input.type==='checkbox'?input.checked:input.value; if(input.getAttribute('data-option')==='tags'&&value){try{value=JSON.parse(value);}catch(e){}} opts[input.getAttribute('data-option')]=value; }); schedule_channel_definitions_sync();
		}
		function remove_manual_channel(serial,index,channel_number) {
			var channels=channel_definitions.meters[serial]||[], channel=channels[index];
			if(!channel || channel.origin!=='manual') return;
			var message=channel_labels.removeConfirm.replace('{channel}',channel_number).replace('{obis}',full_obis(channel)).replace('{uuid}',channel.uuid||'–');
			if(!window.confirm(message)) return;
			try { window.localStorage.removeItem(channel_details_storage_key(serial, channel.uuid)); } catch (error) {}
			channels.splice(index,1); render_channel_editor(serial); update_meter_enabled(serial);
		}
		function add_manual_obis_channel(serial) {
			var value=window.prompt(channel_labels.manualPrompt,'1-0:1.8.0'); var parsed=parse_obis_ui(value); if(!parsed){ if(value!=null) window.alert(channel_labels.unknown); return; }
			var info=catalog_info(value), aggtime=Number((document.getElementById(serial+'_aggtime')||{}).value||0), key=unique_output_key_ui(serial,default_output_key_ui(parsed,info));
			(channel_definitions.meters[serial]||(channel_definitions.meters[serial]=[])).push({uuid:channel_uuid(),enabled:true,origin:'manual',obis:parsed.base,storage:parsed.f,display_name:'',api:'null',aggmode:aggtime>0?info.recommended_aggmode:'none',duplicates:0,api_options:{volkszaehler:{},influxdb:{},mysmartgrid:{}},plugin_output:{enabled:true,key:key.substring(0,64)}}); render_channel_editor(serial);
		}
		document.querySelectorAll('.meter-panel[open] .obis-editor').forEach(function(container){ render_channel_editor(container.id.replace(/_obis_channels$/,'')); });

		function start_obis_discovery(serial) {
			var form = document.getElementById("vzlogger_form");
			if (!form || (form.reportValidity && !form.reportValidity())) return;
			sync_channel_definitions();
			document.getElementById("obis_serial").value = serial;
			obis_job_serial = serial;
			show_obis_search_overlay();
			var data = new FormData(form);
			data.append("ajax", "1");
			data.append("ajaxaction", "obis-start");
			data.append("lang", ui_language);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (status) {
					if (!status.ok || !status.job_id) throw new Error(status.message || obis_text("obis_search_failed_text"));
					obis_job_id = status.job_id;
					obis_job_serial = status.serial || serial;
					poll_obis_discovery();
				})
				.catch(obis_discovery_failed);
		}

		function poll_obis_discovery() {
			fetch(obis_ajax_url("obis-status"), { credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (status) {
					obis_poll_failures = 0;
					if (status.state == "completed") {
						var serial = status.serial || obis_job_serial;
						if (status.restore_failed || status.warning) {
							window.alert($("#obis_search_restore_warning_text").text() || status.warning);
						}
						render_discovered_obis_channels(serial, status.channels || []);
						reset_obis_search_overlay();
						return;
					}
					if (status.state == "cancelled") {
						reset_obis_search_overlay();
						return;
					}
					if (status.state == "failed") {
						obis_discovery_failed(new Error(status.message || obis_text("obis_search_failed_text")));
						return;
					}
					if (status.state == "cancelling") {
						document.getElementById("obis_search_message").textContent = obis_text("obis_search_cancelling_text");
						document.getElementById("obis_search_cancel").disabled = true;
					}
					obis_job_id = status.job_id || obis_job_id;
					obis_job_serial = status.serial || obis_job_serial;
					obis_poll_timer = window.setTimeout(poll_obis_discovery, 1000);
				})
				.catch(function (error) {
					obis_poll_failures++;
					if (obis_poll_failures < 3) {
						obis_poll_timer = window.setTimeout(poll_obis_discovery, 1000);
						return;
					}
					obis_discovery_failed(error);
				});
		}

		function render_discovered_obis_channels(serial, channels) {
			var existing = {};
			(channel_definitions.meters[serial] || []).forEach(function(ch){ existing[full_obis(ch)]=true; });
			channels.forEach(function (channel) {
				var identifier = channel.identifier || "";
				var parsed=parse_obis_ui(identifier); if(!parsed || existing[identifier]) return;
				var info=catalog_info(identifier), aggtime=Number((document.getElementById(serial+'_aggtime')||{}).value||0);
				(channel_definitions.meters[serial]||(channel_definitions.meters[serial]=[])).push({uuid:channel_uuid(),enabled:true,origin:'discovered',obis:parsed.base,storage:parsed.f,display_name:'',api:'null',aggmode:aggtime>0?info.recommended_aggmode:'none',duplicates:0,api_options:{volkszaehler:{},influxdb:{},mysmartgrid:{}},plugin_output:{enabled:true,key:unique_output_key_ui(serial,default_output_key_ui(parsed,info))}}); existing[identifier]=true;
			});
			render_channel_editor(serial);
		}

		function cancel_obis_discovery() {
			if (!obis_job_id) return;
			document.getElementById("obis_search_message").textContent = obis_text("obis_search_cancelling_text");
			document.getElementById("obis_search_cancel").disabled = true;
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "obis-cancel");
			data.append("lang", ui_language);
			data.append("job_id", obis_job_id);
			append_csrf(data);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (status) {
					if (!status.ok) throw new Error(status.message || obis_text("obis_search_failed_text"));
					if (!obis_poll_timer) poll_obis_discovery();
				})
				.catch(obis_discovery_failed);
		}

		function obis_discovery_failed(error) {
			var message = error && error.message ? error.message : obis_text("obis_search_failed_text");
			reset_obis_search_overlay();
			var alert_message = obis_text("obis_search_failed_text") + "\n\n" + message;
			// Yield so the hidden overlay is painted before the blocking alert.
			window.setTimeout(function () { window.alert(alert_message); }, 0);
		}

		function resume_obis_discovery() {
			fetch(obis_ajax_url("obis-status"), { credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (status) {
					if (["starting", "running", "cancelling"].indexOf(status.state) < 0) return;
					obis_job_id = status.job_id || "";
					obis_job_serial = status.serial || "";
					show_obis_search_overlay();
					if (status.state == "cancelling") {
						document.getElementById("obis_search_message").textContent = obis_text("obis_search_cancelling_text");
						document.getElementById("obis_search_cancel").disabled = true;
					}
					obis_poll_timer = window.setTimeout(poll_obis_discovery, 1000);
				});
		}

		window.addEventListener("pageshow", function () {
			reset_obis_search_overlay();
			resume_obis_discovery();
			poll_service_status();
		});

		smartmeterSetToggleValue("bridge_enabled", initial_bridge_enabled);
		smartmeterSetToggleValue("vzlogger_enabled", initial_vzlogger_enabled);
		smartmeterSetToggleValue("expert_mode", expert_mode_active ? "1" : "0");
		smartmeterSetToggleValue("sendudp", settings_defaults.sendudp);
		smartmeterSetToggleValue("bridge_mqtt_enabled", settings_defaults.bridgeMqttEnabled);
		smartmeterSetToggleValue("http_cache_enabled", settings_defaults.httpCacheEnabled);
		$("#rescan_ir_heads, #http_cache_link, #vzlogger_live_link, #vzlogger_rendered_link").off("click.smartmeterDisabled").on("click.smartmeterDisabled", function (event) {
			if ($(this).attr("aria-disabled") == "true") event.preventDefault();
		});
		smartmeterSetToggleValue("vzlogger_service_debug", settings_defaults.serviceDebug);
		$("#vzlogger_loglevel").val(settings_defaults.logLevel);
		smartmeterSetToggleValue("vzlogger_localenabled", settings_defaults.localEnabled);
		smartmeterSetToggleValue("vzlogger_localindex", settings_defaults.localIndex);
		smartmeterSetToggleValue("vzlogger_mqttenabled", settings_defaults.mqttEnabled);
		smartmeterSetToggleValue("vzlogger_mqttretain", settings_defaults.mqttRetain);
		smartmeterSetToggleValue("vzlogger_mqttrawandagg", settings_defaults.mqttRawAndAgg);
		$("#vzlogger_mqttqos").val(settings_defaults.mqttQos);
		smartmeterSetToggleValue("vzlogger_mqtttimestamp", settings_defaults.mqttTimestamp);
		$("#vzlogger_cacheudpinterval").val(settings_defaults.cacheUdpInterval);
		update_activation_dirty_hints();
		disable_cron();
		update_bridge_output_controls();

		function disable_cron() {
			update_all_control_states();
		}

		function set_control_disabled(selector, disabled) {
			var controls = $(selector);
			controls.each(function() {
				var control = $(this);
				if (control.hasClass("smartmeter-toggle-input")) smartmeterSetToggleDisabled(this, disabled);
				else control.prop("disabled", disabled);
				control.toggleClass("is-disabled", disabled);
				control.closest(".lb-input, .lb-select, .lb-toggle, .lb-checkbox").toggleClass("is-disabled", disabled);
				var inline_setting = control.closest(".service-inline-setting");
				if (inline_setting.length) inline_setting.toggleClass("setting-disabled-inline", disabled);
				else control.closest("tr").toggleClass("setting-disabled", disabled);
			});
		}

		function set_anchor_disabled(selector, disabled) {
			smartmeterSetLinkDisabled(document.querySelectorAll(selector), disabled);
		}

		function service_reason(id) {
			return obis_text("service_reason_" + id);
		}

		function update_service_action_states(ui) {
			if (!last_service_snapshot || !last_service_snapshot.services) {
				var waiting_reason = service_reason("waiting");
				$(".service-control-button").prop("disabled", true).addClass("is-disabled").each(function () {
					set_service_button_title($(this), waiting_reason);
				});
				$("#vzlogger_service_action_reason, #bridge_service_action_reason").text(waiting_reason);
				return;
			}
			var services = last_service_snapshot.services;
			var config = last_service_snapshot.config || {};
			var applied = last_service_snapshot.applied || {};
			var saved_vzlogger = !!applied.vzlogger_enabled;
			var saved_bridge = saved_vzlogger && !!applied.bridge_enabled;
			var busy_reason = service_reason("busy");
			var expert_invalid = !!config.expert_mode && !config.expert_valid;
			var expert_unapplied = !!config.expert_mode && !config.expert_applied;
			var vz_reason = !saved_vzlogger ? service_reason("activation") : (expert_invalid || expert_unapplied || !config.valid) ? service_reason("config") : "";
			var bridge_reason = !saved_bridge ? service_reason("activation") : (expert_invalid || expert_unapplied || !config.valid) ? service_reason("config") :
				(!applied.mqtt_enabled || !config.mqtt_enabled ? service_reason("mqtt") : "");
			var vz_enabled = saved_vzlogger && ui.vzlogger && !!config.valid && !expert_invalid && !expert_unapplied && !service_action_running;
			var bridge_enabled = saved_bridge && ui.bridge && !!config.valid && !expert_invalid && !expert_unapplied && !!applied.mqtt_enabled && !!config.mqtt_enabled && !service_action_running;
			set_control_disabled("#save_apply_button", expert_invalid || configuration_action_running || service_action_running);
			if (expert_invalid && config.expert_message) {
				show_service_feedback(config.expert_message, "error", 0);
			} else if (config.expert_mode && config.expert_valid) {
				var feedback = document.getElementById("service_action_feedback");
				if (feedback.classList.contains("is-error")) {
					show_service_feedback(config.expert_message || "", "success", 0);
				}
			}
			$("#vzlogger_service_action_reason").text(vz_enabled ? "" : (service_action_running ? busy_reason : vz_reason));
			$("#bridge_service_action_reason").text(bridge_enabled ? "" : (service_action_running ? busy_reason : bridge_reason));
			set_service_button_state("vzlogger_start_button", !services.vzlogger.running, vz_enabled, service_action_running ? busy_reason : vz_reason);
			set_service_button_state("vzlogger_restart_button", true, vz_enabled, service_action_running ? busy_reason : vz_reason);
			set_service_button_state("vzlogger_stop_button", !!services.vzlogger.running, !!services.vzlogger.running && !service_action_running, service_action_running ? busy_reason : "");
			set_service_button_state("bridge_start_button", !services.bridge.running, bridge_enabled, service_action_running ? busy_reason : bridge_reason);
			set_service_button_state("bridge_restart_button", true, bridge_enabled, service_action_running ? busy_reason : bridge_reason);
			set_service_button_state("bridge_stop_button", !!services.bridge.running, !!services.bridge.running && !service_action_running, service_action_running ? busy_reason : "");
			set_anchor_disabled("#vzlogger_live_link, #vzlogger_rendered_link", !services.vzlogger.running);
		}

		function update_all_control_states() {
			var ui = {
				vzlogger: smartmeterToggleValue("vzlogger_enabled") == "1",
				local: smartmeterToggleValue("vzlogger_localenabled") == "1",
				mqtt: expert_mode_active ? expert_mqtt_enabled : smartmeterToggleValue("vzlogger_mqttenabled") == "1",
				bridge_switch: smartmeterToggleValue("bridge_enabled") == "1",
				bridge_mqtt: smartmeterToggleValue("bridge_mqtt_enabled") == "1",
				http_cache: smartmeterToggleValue("http_cache_enabled") == "1",
				udp: smartmeterToggleValue("sendudp") == "1",
				source_timestamp: expert_mode_active ? expert_mqtt_timestamp : smartmeterToggleValue("vzlogger_mqtttimestamp") == "1"
			};
			if (!ui.source_timestamp && ui.bridge_mqtt) {
				smartmeterSetToggleValue("bridge_mqtt_enabled", "0");
				ui.bridge_mqtt = false;
			}
			ui.bridge_available = ui.vzlogger && ui.mqtt;
			ui.bridge = ui.bridge_available && ui.bridge_switch;

			$("#vzlogger_configuration_section").toggleClass("configuration-disabled", !ui.vzlogger || expert_mode_active);
			set_control_disabled("#vzlogger_service_debug, #vzlogger_loglevel, #vzlogger_retry, #vzlogger_localenabled, #vzlogger_mqttenabled", !ui.vzlogger);
			set_control_disabled("#vzlogger_localport, #vzlogger_localindex, #vzlogger_localtimeout, #vzlogger_localbuffer", !(ui.vzlogger && ui.local));
			set_control_disabled("#vzlogger_mqtthost, #vzlogger_mqttport, #vzlogger_mqttcafile, #vzlogger_mqttcapath, #vzlogger_mqttcertfile, #vzlogger_mqttkeyfile, #vzlogger_mqttkeypass, #vzlogger_mqttkeypass_reset, #vzlogger_mqttkeepalive, #mqtttopic, #vzlogger_mqttid, #vzlogger_mqttuser, #vzlogger_mqttpass, #vzlogger_mqttpass_reset, #vzlogger_mqttretain, #vzlogger_mqttrawandagg, #vzlogger_mqttqos, #vzlogger_mqtttimestamp", !(ui.vzlogger && ui.mqtt));
			$("#mqtt_settings_panel h4").closest("tr").toggleClass("setting-disabled", !(ui.vzlogger && ui.mqtt));
			$("#mqtt_settings_panel > p").toggleClass("setting-disabled-inline", !(ui.vzlogger && ui.mqtt));

			set_anchor_disabled("#rescan_ir_heads", !ui.vzlogger);
			$("#rescan_ir_heads").closest("tr").toggleClass("setting-disabled", !ui.vzlogger);
			$(".meter-panel").each(function () { update_meter_enabled(this.id.substring("meter_".length)); });

			set_control_disabled("#read", !ui.bridge_available);
			$("#bridge_configuration_section").toggleClass("configuration-disabled", !ui.bridge);
			set_control_disabled("#http_cache_enabled, #sendudp", !ui.bridge);
			set_control_disabled("#bridge_mqtt_enabled", !ui.bridge || !ui.source_timestamp);
			$("#bridge_mqtt_timestamp_unavailable").prop("hidden", !!ui.source_timestamp);
			$("#bridge_settings_panel > p").toggleClass("setting-disabled-inline", !ui.bridge);
			$("#bridge_settings_panel h4").closest("tr").toggleClass("setting-disabled", !ui.bridge);
			$("#bridge_mqtt_topic_row").toggleClass("setting-disabled", !ui.bridge || !ui.bridge_mqtt);
			$("#http_cache_status_row").toggleClass("setting-disabled", !ui.bridge || !ui.http_cache);
			var cache_available = $("#http_cache_link").attr("data-cache-available") == "1";
			set_anchor_disabled("#http_cache_link", !ui.bridge || !ui.http_cache || !cache_available);
			set_control_disabled("#udpport", !ui.bridge || !ui.udp);
			$("#labeludpport").toggleClass("is-disabled", !ui.bridge || !ui.udp);
			set_control_disabled("#vzlogger_cacheudpinterval", !ui.bridge || (!ui.http_cache && !ui.udp));
			if (expert_mode_active) {
				$("#vzlogger_configuration_section").find("input, select, textarea, button").not("#expert_mode").each(function () {
					set_control_disabled($(this), true);
				});
				set_anchor_disabled("#rescan_ir_heads", true);
			}

			update_service_action_states(ui);
		}

		function handle_source_timestamp_change() {
			if (smartmeterToggleValue("vzlogger_mqtttimestamp") != "1") smartmeterSetToggleValue("bridge_mqtt_enabled", "0");
			update_all_control_states();
		}

		function set_expert_mode(value) {
			var control = $("#expert_mode");
			control.prop("disabled", true).addClass("is-disabled");
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "expert-mode");
			data.append("lang", ui_language);
			data.append("enabled", value == "1" ? "1" : "0");
			append_csrf(data);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (response) {
					if (!response.ok) throw new Error(response.message || obis_text("expert_mode_enable_failed_text"));
					expert_mode_active = !!response.expert_mode;
					expert_source_present = expert_source_present || expert_mode_active;
					expert_runtime_applied = !!response.expert_applied;
					expert_mqtt_enabled = !!response.mqtt_enabled;
					expert_mqtt_timestamp = !!response.mqtt_timestamp;
					smartmeterSetToggleValue("expert_mode", expert_mode_active ? "1" : "0");
					smartmeterSetToggleDisabled("expert_mode", false);
					control.removeClass("is-disabled");
					render_expert_mode_state();
					if (last_service_snapshot && last_service_snapshot.config) {
						last_service_snapshot.config.expert_mode = expert_mode_active;
						last_service_snapshot.config.expert_valid = !!response.expert_valid;
						last_service_snapshot.config.expert_applied = !!response.expert_applied;
						last_service_snapshot.config.expert_present = expert_source_present;
						last_service_snapshot.config.expert_message = response.validation_message || "";
					}
					update_all_control_states();
					poll_service_status();
				})
				.catch(function (error) {
					smartmeterSetToggleValue("expert_mode", expert_mode_active ? "1" : "0");
					smartmeterSetToggleDisabled("expert_mode", false);
					control.removeClass("is-disabled");
					window.alert(error.message || obis_text("expert_mode_enable_failed_text"));
				});
		}

		function render_expert_mode_state() {
			var button = $("#show_generated_config");
			var label = obis_text(expert_mode_active ? "edit_expert_config_text" : "show_generated_config_text");
			var help = obis_text(expert_mode_active ? "edit_expert_config_help_text" : "show_generated_config_help_text");
			var text = button.find(".lb-btn-text");
			if (text.length) text.text(label); else button.text(label);
			button.attr("title", help);
			var icon = button.find(".pi");
			if (icon.length) icon.removeClass("pi-pencil pi-search").addClass(expert_mode_active ? "pi-pencil" : "pi-search");
			if (expert_mode_active) button.removeAttr("rel"); else button.attr("rel", "noopener");
			$("#generated_config_help").text(help + (expert_mode_active ? " " + obis_text("reset_expert_config_help_text") : ""));
			$("#expert_mode_notice").prop("hidden", !expert_mode_active);
			$("#reset_expert_config_container").prop("hidden", !expert_mode_active).toggle(expert_mode_active);
		}

		function reset_expert_configuration() {
			if (!expert_mode_active || !window.confirm(obis_text("reset_expert_config_confirm_text"))) return;
			var button = $("#reset_expert_config");
			button.prop("disabled", true).addClass("is-disabled");
			var data = new FormData();
			data.append("ajax", "1");
			data.append("ajaxaction", "expert-reset");
			data.append("lang", ui_language);
			append_csrf(data);
			fetch("./index.cgi", { method: "POST", body: data, credentials: "same-origin", cache: "no-store" })
				.then(function (response) { return response.json(); })
				.then(function (response) {
					if (!response.ok) throw new Error(response.message || obis_text("reset_expert_config_failed_text"));
					expert_source_present = true;
				expert_mqtt_enabled = !!response.mqtt_enabled;
				expert_mqtt_timestamp = !!response.mqtt_timestamp;
					if (last_service_snapshot && last_service_snapshot.config) {
						last_service_snapshot.config.expert_valid = !!response.expert_valid;
						last_service_snapshot.config.expert_applied = !!response.expert_applied;
						last_service_snapshot.config.expert_present = true;
						last_service_snapshot.config.expert_message = response.validation_message || "";
					}
					var feedback = document.getElementById("service_action_feedback");
					feedback.textContent = response.message || response.validation_message || "";
					feedback.classList.remove("is-error");
					feedback.classList.toggle("is-visible", !!feedback.textContent);
					update_all_control_states();
					poll_service_status();
				})
				.catch(function (error) {
					window.alert(error.message || obis_text("reset_expert_config_failed_text"));
				})
				.then(function () {
					button.prop("disabled", false).removeClass("is-disabled");
				});
		}

		window.addEventListener("message", function (event) {
			if (event.origin != window.location.origin || !event.data || event.data.type != "smartmeter-vzlogger-expert") return;
			var feedback = document.getElementById("service_action_feedback");
			feedback.textContent = event.data.message || "";
			feedback.classList.toggle("is-error", !event.data.valid);
			feedback.classList.add("is-visible");
			schedule_service_poll();
		});

		function update_activation_dirty_hints() {
			var activation_changed = smartmeterToggleValue("vzlogger_enabled") != initial_vzlogger_enabled;
			var bridge_changed = smartmeterToggleValue("bridge_enabled") != initial_bridge_enabled;
			$("#vzlogger_activation_unsaved").prop("hidden", !activation_changed);
			$("#bridge_activation_unsaved").prop("hidden", !bridge_changed);
		}

		function update_vzlogger_controls() { update_activation_dirty_hints(); update_all_control_states(); }
		function update_local_controls() { update_all_control_states(); }
		function update_mqtt_controls() { update_all_control_states(); }
		function update_bridge_controls() { update_activation_dirty_hints(); update_all_control_states(); }
		function update_bridge_output_controls() { update_all_control_states(); }

		function update_meter_protocol(serial) {
			var panelElement = document.getElementById("meter_" + serial);
			var selectElement = document.getElementById(serial + "_meter");
			if (!panelElement || !selectElement) return;
			var panel = $(panelElement);
			var mode = selectElement.value;
			panel.find(".meter-field").each(function () {
				var protocols = (this.getAttribute("data-protocols") || "").split(/\s+/);
				$(this).toggle(protocols.indexOf(mode) >= 0);
			});
			var fieldOrder = {
				sml: ["interval", "pullseq", "baudrate", "parity", "use_local_time"],
				d0: ["interval", "dump_file", "pullseq", "ackseq", "baudrate", "baudrate_read", "parity", "wait_sync", "read_timeout", "baudrate_change_delay"],
				oms: ["baudrate", "key", "mbus_debug", "use_local_time"]
			};
			var userAnchor = panel.find(".meter-user-settings").first();
			(fieldOrder[mode] || []).forEach(function (field) {
				userAnchor.before(panel.find('.meter-field[data-meter-field="' + field + '"]'));
			});
			panel.find(".meter-user-settings").toggle(mode == "user");
			panel.find(".meter-common-field").toggle(["sml", "d0", "oms"].indexOf(mode) >= 0);
			panel.find(".meter-obis-settings").toggle(["sml", "d0", "oms"].indexOf(mode) >= 0);
			var channelEditor = document.getElementById(serial + "_obis_channels");
			if (channelEditor) { channelEditor.setAttribute("data-protocol", mode); render_channel_editor(serial); }
			panel.find(".meter-template-row").toggle(["sml", "d0"].indexOf(mode) >= 0);
			update_meter_template_options(serial, mode);
			var omsUnsupported = mode == "oms" && panel.attr("data-oms-supported") != "1";
			panel.find(".meter-oms-runtime-warning").toggle(omsUnsupported);
			var selectedOption = selectElement.options[selectElement.selectedIndex];
			panel.find(".meter-protocol-summary").text(selectedOption ? selectedOption.text : "");
			var warningKind = panel.attr("data-warning-kind") || "";
			var showWarning = !warningKind || warningKind == mode;
			panel.find(".meter-warning-icon, .meter-primary-warning").toggle(showWarning);
			update_meter_enabled(serial);
		}


		function refresh_meter_select(select) {
			if (select) select.dispatchEvent(new Event("change", { bubbles: false }));
		}

		function update_meter_template_options(serial, protocol) {
			var select = document.getElementById(serial + "_template");
			if (!select) return;
			var placeholder = select.getAttribute("data-placeholder") || "";
			select.options.length = 0;
			select.add(new Option(placeholder, ""));
			meter_templates.forEach(function (template) {
				if (template.protocol == protocol) select.add(new Option(template.label, template.id));
			});
			select.value = "";
			document.getElementById(serial + "_template_warning").hidden = true;
			refresh_meter_select(select);
		}

		function apply_meter_template(serial) {
			var protocol = $("#" + serial + "_meter").val();
			var select = document.getElementById(serial + "_template");
			if (!select || !select.value) return;
			var template = meter_templates.find(function (candidate) { return candidate.id == select.value && candidate.protocol == protocol; });
			if (!template) return;
			var operating_baudrate = protocol == "sml" ? template.read_baudrate : template.initial_baudrate;
			$("#" + serial + "_baudrate").val(String(operating_baudrate));
			$("#" + serial + "_paritymode").val(template.serial_mode);
			if (protocol == "d0") {
				$("#" + serial + "_baudrateread").val(String(template.read_baudrate));
				$("#" + serial + "_readtimeout").val(String(template.read_timeout));
			}
			refresh_meter_select(document.getElementById(serial + "_paritymode"));
			document.getElementById(serial + "_template_unsaved").hidden = false;
			document.getElementById(serial + "_template_warning").hidden = !template.limited;
		}

		function update_meter_enabled(serial) {
			var panel = $("#meter_" + serial);
			if (!panel.length) return;
			var mode = $("#" + serial + "_meter").val();
			var standard_meter = ["sml", "d0", "oms"].indexOf(mode) >= 0;
			var global_disabled = smartmeterToggleValue("vzlogger_enabled") != "1";
			var runtime_action_disabled = saved_vzlogger_enabled != "1";
			var meter_disabled = standard_meter && smartmeterToggleValue(serial + "_enabled") == "0";
			var name_control = $("#" + serial + "_name");
			var enabled_control = $("#" + serial + "_enabled");
			var remove_control = panel.find(".meter-remove-button");
			var dependent_controls = panel.find("input, select, textarea, button").not(name_control).not(enabled_control).not(remove_control).not(".meter-remove-marker");
			set_control_disabled(name_control, global_disabled);
			set_control_disabled(enabled_control, global_disabled);
			set_control_disabled(dependent_controls, global_disabled || meter_disabled);
			set_control_disabled(panel.find("input.ch-storage"), global_disabled || meter_disabled || mode == "oms");
			set_control_disabled(panel.find("button.ch-storage-clear"), global_disabled || meter_disabled || mode == "oms");
			set_control_disabled(panel.find("select.ch-agg"), global_disabled || meter_disabled || Number($("#" + serial + "_aggtime").val() || 0) <= 0);
			set_control_disabled($("#" + serial + "_aggfixedinterval"), global_disabled || meter_disabled || Number($("#" + serial + "_aggtime").val() || 0) <= 0);
			panel.find(".obis-channel-card").each(function () {
				var api = $(this).find("select.ch-api").val();
				set_control_disabled($(this).find("input.ch-duplicates"), global_disabled || meter_disabled || ["volkszaehler", "influxdb"].indexOf(api) < 0);
				set_control_disabled($(this).find("input.ch-output-key"), global_disabled || meter_disabled || !$(this).find("input.ch-output").prop("checked"));
			});
			set_control_disabled(remove_control, global_disabled);
			var rows = panel.find("table.settings-table").first().children("tbody").children("tr");
			rows.each(function () {
				var keep_active = $(this).hasClass("meter-name-row") || $(this).hasClass("meter-enabled-row");
				$(this).toggleClass("setting-disabled", global_disabled || (meter_disabled && !keep_active));
			});
			var oms_unsupported = mode == "oms" && panel.attr("data-oms-supported") != "1";
			set_control_disabled(panel.find(".obis-discovery"), global_disabled || runtime_action_disabled || meter_disabled || oms_unsupported);
			panel.find(".obis-runtime-action-reason").prop("hidden", !runtime_action_disabled).toggle(runtime_action_disabled);
		}

		function stage_meter_removal(serial) {
			var panel = $("#meter_" + serial);
			if (!panel.length || !window.confirm(obis_text("remove_meter_confirm_text"))) return;
			panel.find(".meter-remove-marker").prop("disabled", false);
			panel.closest("tr").hide();
		}

		function collapsible_storage_key(element) {
			return "smartmeter-vzlogger-collapsible:" + window.location.pathname + ":" + element.id;
		}

		function restore_collapsible_state(element) {
			if (!element || !element.id) return;
			try {
				var state = window.localStorage.getItem(collapsible_storage_key(element));
				if (state == "open") element.open = true;
				else if (state == "closed") element.open = false;
			} catch (error) {}
		}

		function initialize_collapsible_persistence() {
			document.querySelectorAll("#vzlogger_form details.lb-collapsible[id]").forEach(function (element) {
				if (element.dataset.persistenceReady == "1") return;
				element.dataset.persistenceReady = "1";
				element.addEventListener("toggle", function () {
					try { window.localStorage.setItem(collapsible_storage_key(element), element.open ? "open" : "closed"); } catch (error) {}
				});
				restore_collapsible_state(element);
			});
		}

		function initialize_meter_panel(panel, enhance) {
			if (!panel) return;
			if (enhance) restore_collapsible_state(panel);
			if (SmartMeterVZLoggerUi.initializeDeferredPanel(panel, function (target) { initialize_meter_panel(target, false); })) return;
			panel.dataset.deferredInitialization = "0";
			var serial = panel.id.substring("meter_".length);
			var values = {
				meter: panel.getAttribute("data-current-mode") || "0",
				enabled: panel.getAttribute("data-meter-enabled") || "1",
				allowskip: panel.getAttribute("data-allowskip") || "1",
				aggfixedinterval: panel.getAttribute("data-aggfixedinterval") || "0",
				paritymode: panel.getAttribute("data-parity") || "8n1",
				uselocaltime: panel.getAttribute("data-local-time") || "0",
				waitsync: panel.getAttribute("data-wait-sync") || "off",
				mbusdebug: panel.getAttribute("data-mbus-debug") || "0"
			};
			Object.keys(values).forEach(function (suffix) {
				var control = document.getElementById(serial + "_" + suffix);
				if (!control) return;
				if (control.classList.contains("smartmeter-toggle-input")) smartmeterSetToggleValue(control, values[suffix]);
				else control.value = values[suffix];
			});
			smartmeterInitializeToggles(panel);
			update_meter_protocol(serial);
		}

		$(".meter-panel").each(function () { initialize_meter_panel(this, false); });
		initialize_collapsible_persistence();
		update_recovery_controls();
		document.getElementById("service_action_overlay").addEventListener("cancel", function (event) {
			if (!service_action_running) return;
			event.preventDefault();
			hide_service_action_overlay();
		});
		document.getElementById("vzlogger_form").addEventListener("submit", sync_channel_definitions);
		window.addEventListener("pagehide", sync_channel_definitions);
