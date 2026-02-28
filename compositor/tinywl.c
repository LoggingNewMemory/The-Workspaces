#include <assert.h>
#include <getopt.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

enum tinywl_cursor_mode {
	TINYWL_CURSOR_PASSTHROUGH,
	TINYWL_CURSOR_MOVE,
	TINYWL_CURSOR_RESIZE,
};

struct tinywl_server {
	struct wl_display *wl_display;
	struct wlr_backend *backend;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_scene *scene;
	struct wlr_scene_output_layout *scene_layout;

	struct wlr_xdg_shell *xdg_shell;
	struct wl_listener new_xdg_toplevel;
	struct wl_listener new_xdg_popup;
	struct wl_list toplevels;

	struct wlr_cursor *cursor;
	struct wlr_xcursor_manager *cursor_mgr;
	struct wl_listener cursor_motion;
	struct wl_listener cursor_motion_absolute;
	struct wl_listener cursor_button;
	struct wl_listener cursor_axis;
	struct wl_listener cursor_frame;

	struct wlr_seat *seat;
	struct wl_listener new_input;
	struct wl_listener request_cursor;
	struct wl_listener request_set_selection;
	struct wl_list keyboards;
	enum tinywl_cursor_mode cursor_mode;
	struct tinywl_toplevel *grabbed_toplevel;
	double grab_x, grab_y;
	struct wlr_box grab_geobox;
	uint32_t resize_edges;

	struct wlr_output_layout *output_layout;
	struct wl_listener layout_change; // <-- Added listener for output resizing
	struct wl_list outputs;
	struct wl_listener new_output;
    
	struct wl_event_source *dock_ipc_timer;
	int last_hover; // 0 = none, 1 = left, 2 = right
};

struct tinywl_output {
	struct wl_list link;
	struct tinywl_server *server;
	struct wlr_output *wlr_output;
	struct wl_listener frame;
	struct wl_listener request_state;
	struct wl_listener destroy;
};

struct tinywl_toplevel {
	struct wl_list link;
	struct tinywl_server *server;
	struct wlr_xdg_toplevel *xdg_toplevel;
	struct wlr_scene_tree *scene_tree;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener commit;
	struct wl_listener destroy;
	struct wl_listener request_move;
	struct wl_listener request_resize;
	struct wl_listener request_maximize;
	struct wl_listener request_fullscreen;
    
	int docked_side; // 0 = not docked, 1 = left, 2 = right
    
	// Maximize State Tracking
	bool maximized;
	double saved_x;
	double saved_y;
	struct wlr_box saved_geometry;
};

struct tinywl_popup {
	struct wlr_xdg_popup *xdg_popup;
	struct wl_listener commit;
	struct wl_listener destroy;
};

struct tinywl_keyboard {
	struct wl_list link;
	struct tinywl_server *server;
	struct wlr_keyboard *wlr_keyboard;

	struct wl_listener modifiers;
	struct wl_listener key;
	struct wl_listener destroy;
};

// Forward declaration for state updates
static void update_workspace_state(struct tinywl_server *server);

static void focus_toplevel(struct tinywl_toplevel *toplevel) {
	if (toplevel == NULL) {
		return;
	}
	struct tinywl_server *server = toplevel->server;
	struct wlr_seat *seat = server->seat;
	struct wlr_surface *prev_surface = seat->keyboard_state.focused_surface;
	struct wlr_surface *surface = toplevel->xdg_toplevel->base->surface;
	if (prev_surface == surface) {
		return;
	}
	if (prev_surface) {
		struct wlr_xdg_toplevel *prev_toplevel =
			wlr_xdg_toplevel_try_from_wlr_surface(prev_surface);
		if (prev_toplevel != NULL) {
			wlr_xdg_toplevel_set_activated(prev_toplevel, false);
		}
	}
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(seat);
	wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
	wl_list_remove(&toplevel->link);
	wl_list_insert(&server->toplevels, &toplevel->link);
	wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, true);
	if (keyboard != NULL) {
		wlr_seat_keyboard_notify_enter(seat, surface,
			keyboard->keycodes, keyboard->num_keycodes, &keyboard->modifiers);
	}
}

static void keyboard_handle_modifiers(struct wl_listener *listener, void *data) {
	struct tinywl_keyboard *keyboard = wl_container_of(listener, keyboard, modifiers);
	wlr_seat_set_keyboard(keyboard->server->seat, keyboard->wlr_keyboard);
	wlr_seat_keyboard_notify_modifiers(keyboard->server->seat,
		&keyboard->wlr_keyboard->modifiers);
}

static bool handle_keybinding(struct tinywl_server *server, xkb_keysym_t sym) {
	switch (sym) {
	case XKB_KEY_Escape:
		wl_display_terminate(server->wl_display);
		break;
	case XKB_KEY_F1:
		if (wl_list_length(&server->toplevels) < 2) {
			break;
		}
		struct tinywl_toplevel *next_toplevel =
			wl_container_of(server->toplevels.prev, next_toplevel, link);
		focus_toplevel(next_toplevel);
		break;
	default:
		return false;
	}
	return true;
}

static void keyboard_handle_key(struct wl_listener *listener, void *data) {
	struct tinywl_keyboard *keyboard = wl_container_of(listener, keyboard, key);
	struct tinywl_server *server = keyboard->server;
	struct wlr_keyboard_key_event *event = data;
	struct wlr_seat *seat = server->seat;

	uint32_t keycode = event->keycode + 8;
	const xkb_keysym_t *syms;
	int nsyms = xkb_state_key_get_syms(keyboard->wlr_keyboard->xkb_state, keycode, &syms);

	bool handled = false;
	uint32_t modifiers = wlr_keyboard_get_modifiers(keyboard->wlr_keyboard);
	if ((modifiers & WLR_MODIFIER_ALT) && event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		for (int i = 0; i < nsyms; i++) {
			handled = handle_keybinding(server, syms[i]);
		}
	}

	if (!handled) {
		wlr_seat_set_keyboard(seat, keyboard->wlr_keyboard);
		wlr_seat_keyboard_notify_key(seat, event->time_msec, event->keycode, event->state);
	}
}

static void keyboard_handle_destroy(struct wl_listener *listener, void *data) {
	struct tinywl_keyboard *keyboard = wl_container_of(listener, keyboard, destroy);
	wl_list_remove(&keyboard->modifiers.link);
	wl_list_remove(&keyboard->key.link);
	wl_list_remove(&keyboard->destroy.link);
	wl_list_remove(&keyboard->link);
	free(keyboard);
}

static void server_new_keyboard(struct tinywl_server *server, struct wlr_input_device *device) {
	struct wlr_keyboard *wlr_keyboard = wlr_keyboard_from_input_device(device);

	struct tinywl_keyboard *keyboard = calloc(1, sizeof(*keyboard));
	keyboard->server = server;
	keyboard->wlr_keyboard = wlr_keyboard;

	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);

	wlr_keyboard_set_keymap(wlr_keyboard, keymap);
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);
	wlr_keyboard_set_repeat_info(wlr_keyboard, 25, 600);

	keyboard->modifiers.notify = keyboard_handle_modifiers;
	wl_signal_add(&wlr_keyboard->events.modifiers, &keyboard->modifiers);
	keyboard->key.notify = keyboard_handle_key;
	wl_signal_add(&wlr_keyboard->events.key, &keyboard->key);
	keyboard->destroy.notify = keyboard_handle_destroy;
	wl_signal_add(&device->events.destroy, &keyboard->destroy);

	wlr_seat_set_keyboard(server->seat, keyboard->wlr_keyboard);
	wl_list_insert(&server->keyboards, &keyboard->link);
}

static void server_new_pointer(struct tinywl_server *server, struct wlr_input_device *device) {
	wlr_cursor_attach_input_device(server->cursor, device);
}

static void server_new_input(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, new_input);
	struct wlr_input_device *device = data;
	switch (device->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:
		server_new_keyboard(server, device);
		break;
	case WLR_INPUT_DEVICE_POINTER:
		server_new_pointer(server, device);
		break;
	default:
		break;
	}
	uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
	if (!wl_list_empty(&server->keyboards)) {
		caps |= WL_SEAT_CAPABILITY_KEYBOARD;
	}
	wlr_seat_set_capabilities(server->seat, caps);
}

static void seat_request_cursor(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, request_cursor);
	struct wlr_seat_pointer_request_set_cursor_event *event = data;
	struct wlr_seat_client *focused_client = server->seat->pointer_state.focused_client;
	if (focused_client == event->seat_client) {
		wlr_cursor_set_surface(server->cursor, event->surface, event->hotspot_x, event->hotspot_y);
	}
}

static void seat_request_set_selection(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, request_set_selection);
	struct wlr_seat_request_set_selection_event *event = data;
	wlr_seat_set_selection(server->seat, event->source, event->serial);
}

static struct tinywl_toplevel *desktop_toplevel_at(
		struct tinywl_server *server, double lx, double ly,
		struct wlr_surface **surface, double *sx, double *sy) {
	struct wlr_scene_node *node = wlr_scene_node_at(&server->scene->tree.node, lx, ly, sx, sy);
	if (node == NULL || node->type != WLR_SCENE_NODE_BUFFER) {
		return NULL;
	}
	struct wlr_scene_buffer *scene_buffer = wlr_scene_buffer_from_node(node);
	struct wlr_scene_surface *scene_surface = wlr_scene_surface_try_from_buffer(scene_buffer);
	if (!scene_surface) {
		return NULL;
	}

	*surface = scene_surface->surface;
	struct wlr_scene_tree *tree = node->parent;
	while (tree != NULL && tree->node.data == NULL) {
		tree = tree->node.parent;
	}
	return tree->node.data;
}

static void reset_cursor_mode(struct tinywl_server *server) {
	server->cursor_mode = TINYWL_CURSOR_PASSTHROUGH;
	server->grabbed_toplevel = NULL;
}

static void process_cursor_move(struct tinywl_server *server) {
	struct tinywl_toplevel *toplevel = server->grabbed_toplevel;
	wlr_scene_node_set_position(&toplevel->scene_tree->node,
		server->cursor->x - server->grab_x,
		server->cursor->y - server->grab_y);

	// Fetch dynamic output width for accurate hovering
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, NULL, &box);
	int out_width = box.width > 0 ? box.width : 1920;

	// --- NATIVE EDGE HOVER DETECTION ---
	int current_hover = 0;
	if (server->cursor->x < 40) current_hover = 1;       // Left Edge
	else if (server->cursor->x > out_width - 40) current_hover = 2; // Right Edge

	if (server->last_hover != current_hover) {
		server->last_hover = current_hover;
		update_workspace_state(server);
	}
}

static void process_cursor_resize(struct tinywl_server *server) {
	struct tinywl_toplevel *toplevel = server->grabbed_toplevel;
	double border_x = server->cursor->x - server->grab_x;
	double border_y = server->cursor->y - server->grab_y;
	int new_left = server->grab_geobox.x;
	int new_right = server->grab_geobox.x + server->grab_geobox.width;
	int new_top = server->grab_geobox.y;
	int new_bottom = server->grab_geobox.y + server->grab_geobox.height;

	if (server->resize_edges & WLR_EDGE_TOP) {
		new_top = border_y;
		if (new_top >= new_bottom) new_top = new_bottom - 1;
	} else if (server->resize_edges & WLR_EDGE_BOTTOM) {
		new_bottom = border_y;
		if (new_bottom <= new_top) new_bottom = new_top + 1;
	}
	if (server->resize_edges & WLR_EDGE_LEFT) {
		new_left = border_x;
		if (new_left >= new_right) new_left = new_right - 1;
	} else if (server->resize_edges & WLR_EDGE_RIGHT) {
		new_right = border_x;
		if (new_right <= new_left) new_right = new_left + 1;
	}

	struct wlr_box *geo_box = &toplevel->xdg_toplevel->base->geometry;
	wlr_scene_node_set_position(&toplevel->scene_tree->node,
		new_left - geo_box->x, new_top - geo_box->y);

	int new_width = new_right - new_left;
	int new_height = new_bottom - new_top;
	wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, new_width, new_height);
}

static void process_cursor_motion(struct tinywl_server *server, uint32_t time) {
	if (server->cursor_mode == TINYWL_CURSOR_MOVE) {
		process_cursor_move(server);
		return;
	} else if (server->cursor_mode == TINYWL_CURSOR_RESIZE) {
		process_cursor_resize(server);
		return;
	}

	double sx, sy;
	struct wlr_seat *seat = server->seat;
	struct wlr_surface *surface = NULL;
	struct tinywl_toplevel *toplevel = desktop_toplevel_at(server,
			server->cursor->x, server->cursor->y, &surface, &sx, &sy);
	if (!toplevel) {
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, "default");
	}
	if (surface) {
		wlr_seat_pointer_notify_enter(seat, surface, sx, sy);
		wlr_seat_pointer_notify_motion(seat, time, sx, sy);
	} else {
		wlr_seat_pointer_clear_focus(seat);
	}
}

static void server_cursor_motion(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, cursor_motion);
	struct wlr_pointer_motion_event *event = data;
	wlr_cursor_move(server->cursor, &event->pointer->base, event->delta_x, event->delta_y);
	process_cursor_motion(server, event->time_msec);
}

static void server_cursor_motion_absolute(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, cursor_motion_absolute);
	struct wlr_pointer_motion_absolute_event *event = data;
	wlr_cursor_warp_absolute(server->cursor, &event->pointer->base, event->x, event->y);
	process_cursor_motion(server, event->time_msec);
}

static void server_cursor_button(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, cursor_button);
	struct wlr_pointer_button_event *event = data;
    
	wlr_seat_pointer_notify_button(server->seat, event->time_msec, event->button, event->state);
            
	if (event->state == WL_POINTER_BUTTON_STATE_RELEASED) {
		// --- NATIVE DRAG & DROP DOCKING ---
		if (server->cursor_mode == TINYWL_CURSOR_MOVE && server->grabbed_toplevel != NULL) {
			struct tinywl_toplevel *toplevel = server->grabbed_toplevel;
			
			// Dynamic output box fetching
			struct wlr_box box;
			wlr_output_layout_get_box(server->output_layout, NULL, &box);
			int out_w = box.width > 0 ? box.width : 1920;
			int out_h = box.height > 0 ? box.height : 1080;
            
			if (server->last_hover == 1) { // Dropped on Left
				toplevel->docked_side = 1;
				wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 1280, 720); // Internal scale
				wlr_scene_node_set_position(&toplevel->scene_tree->node, out_w - 1, out_h - 1); // Keep 1 pixel on screen so it doesn't suspend!
				wlr_scene_node_lower_to_bottom(&toplevel->scene_tree->node); // Hide behind Flutter
				wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, false);
                wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
			} else if (server->last_hover == 2) { // Dropped on Right
				toplevel->docked_side = 2;
				wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 1280, 720);
				wlr_scene_node_set_position(&toplevel->scene_tree->node, out_w - 1, out_h - 1);
				wlr_scene_node_lower_to_bottom(&toplevel->scene_tree->node);
				wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, false);
                wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
			}
            
			server->last_hover = 0;
			update_workspace_state(server);
		}
		reset_cursor_mode(server);
	} else {
		double sx, sy;
		struct wlr_surface *surface = NULL;
		struct tinywl_toplevel *toplevel = desktop_toplevel_at(server, server->cursor->x, server->cursor->y, &surface, &sx, &sy);
		focus_toplevel(toplevel);
	}
}

static void server_cursor_axis(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, cursor_axis);
	struct wlr_pointer_axis_event *event = data;
	wlr_seat_pointer_notify_axis(server->seat, event->time_msec, event->orientation, event->delta,
			event->delta_discrete, event->source, event->relative_direction);
}

static void server_cursor_frame(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, cursor_frame);
	wlr_seat_pointer_notify_frame(server->seat);
}

// --- NEW RESIZE HANDLER: Updates Fullscreen & Workspace sizes on window resize ---
static void server_layout_change(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, layout_change);
	
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, NULL, &box);
	int out_w = box.width > 0 ? box.width : 1920;
	int out_h = box.height > 0 ? box.height : 1080;

	struct tinywl_toplevel *toplevel;
	wl_list_for_each(toplevel, &server->toplevels, link) {
		const char *app_id = toplevel->xdg_toplevel->app_id;
		// If it's the Workspace app, OR a fully maximized/fullscreen app, force resize it dynamically.
		if ((app_id && strstr(app_id, "workspace") != NULL) || toplevel->maximized || toplevel->xdg_toplevel->current.fullscreen) {
			wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
			wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
		}
	}
}

static void output_frame(struct wl_listener *listener, void *data) {
	struct tinywl_output *output = wl_container_of(listener, output, frame);
	struct wlr_scene *scene = output->server->scene;
	struct wlr_scene_output *scene_output = wlr_scene_get_scene_output(scene, output->wlr_output);
	wlr_scene_output_commit(scene_output, NULL);

	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(scene_output, &now);
}

static void output_request_state(struct wl_listener *listener, void *data) {
	struct tinywl_output *output = wl_container_of(listener, output, request_state);
	const struct wlr_output_event_request_state *event = data;
	wlr_output_commit_state(output->wlr_output, event->state);
}

static void output_destroy(struct wl_listener *listener, void *data) {
	struct tinywl_output *output = wl_container_of(listener, output, destroy);
	wl_list_remove(&output->frame.link);
	wl_list_remove(&output->request_state.link);
	wl_list_remove(&output->destroy.link);
	wl_list_remove(&output->link);
	free(output);
}

static void server_new_output(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, new_output);
	struct wlr_output *wlr_output = data;

	wlr_output_init_render(wlr_output, server->allocator, server->renderer);

	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);

	struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
	if (mode != NULL) {
		wlr_output_state_set_mode(&state, mode);
	}

	wlr_output_commit_state(wlr_output, &state);
	wlr_output_state_finish(&state);

	struct tinywl_output *output = calloc(1, sizeof(*output));
	output->wlr_output = wlr_output;
	output->server = server;

	output->frame.notify = output_frame;
	wl_signal_add(&wlr_output->events.frame, &output->frame);
	output->request_state.notify = output_request_state;
	wl_signal_add(&wlr_output->events.request_state, &output->request_state);
	output->destroy.notify = output_destroy;
	wl_signal_add(&wlr_output->events.destroy, &output->destroy);

	wl_list_insert(&server->outputs, &output->link);

	struct wlr_output_layout_output *l_output = wlr_output_layout_add_auto(server->output_layout, wlr_output);
	struct wlr_scene_output *scene_output = wlr_scene_output_create(server->scene, wlr_output);
	wlr_scene_output_layout_add_output(server->scene_layout, l_output, scene_output);
}

// --- IPC BRIDGE: EXPORT FULL WORKSPACE STATE TO FLUTTER ---
static void update_workspace_state(struct tinywl_server *server) {
	FILE *f = fopen("/tmp/workspace_state.json", "w");
	if (!f) return;

	fprintf(f, "{\n  \"hover\": %d,\n", server->last_hover);
    
	// 1. Active Windows (Undocked)
	fprintf(f, "  \"active\": [\n");
	bool first = true;
	struct tinywl_toplevel *toplevel;
	wl_list_for_each(toplevel, &server->toplevels, link) {
		const char *app_id = toplevel->xdg_toplevel->app_id ? toplevel->xdg_toplevel->app_id : "Unknown";
		if (strstr(app_id, "workspace") != NULL || toplevel->docked_side != 0) continue;
		if (!first) fprintf(f, ",\n");
		const char *title = toplevel->xdg_toplevel->title ? toplevel->xdg_toplevel->title : "Unknown Window";
		fprintf(f, "    { \"id\": \"%p\", \"name\": \"%s\", \"title\": \"%s\", \"maximized\": %s }", 
            (void*)toplevel, app_id, title, toplevel->maximized ? "true" : "false");
		first = false;
	}
	fprintf(f, "\n  ],\n");

	// 2. Docked Left
	fprintf(f, "  \"docked_left\": [\n");
	first = true;
	wl_list_for_each(toplevel, &server->toplevels, link) {
		if (toplevel->docked_side != 1) continue;
		const char *app_id = toplevel->xdg_toplevel->app_id ? toplevel->xdg_toplevel->app_id : "Unknown";
		const char *title = toplevel->xdg_toplevel->title ? toplevel->xdg_toplevel->title : "Unknown Window";
		if (!first) fprintf(f, ",\n");
		fprintf(f, "    { \"id\": \"%p\", \"name\": \"%s\", \"title\": \"%s\", \"maximized\": %s }", 
            (void*)toplevel, app_id, title, toplevel->maximized ? "true" : "false");
		first = false;
	}
	fprintf(f, "\n  ],\n");

	// 3. Docked Right
	fprintf(f, "  \"docked_right\": [\n");
	first = true;
	wl_list_for_each(toplevel, &server->toplevels, link) {
		if (toplevel->docked_side != 2) continue;
		const char *app_id = toplevel->xdg_toplevel->app_id ? toplevel->xdg_toplevel->app_id : "Unknown";
		const char *title = toplevel->xdg_toplevel->title ? toplevel->xdg_toplevel->title : "Unknown Window";
		if (!first) fprintf(f, ",\n");
		fprintf(f, "    { \"id\": \"%p\", \"name\": \"%s\", \"title\": \"%s\", \"maximized\": %s }", 
            (void*)toplevel, app_id, title, toplevel->maximized ? "true" : "false");
		first = false;
	}
	fprintf(f, "\n  ]\n}\n");
	fclose(f);
}

// --- IPC LISTENER TO DOCK/UNDOCK/MAXIMIZE FROM FLUTTER UI ---
static int handle_dock_ipc(void *data) {
	struct tinywl_server *server = data;
	FILE *f = fopen("/tmp/dock_action.txt", "r");
	if (f) {
		char action[32];
		void *id = NULL;
		if (fscanf(f, "%31s %p", action, &id) == 2) {
			
			struct wlr_box box;
			wlr_output_layout_get_box(server->output_layout, NULL, &box);
			int out_w = box.width > 0 ? box.width : 1920;
			int out_h = box.height > 0 ? box.height : 1080;

			struct tinywl_toplevel *toplevel;
			wl_list_for_each(toplevel, &server->toplevels, link) {
				if ((void*)toplevel == id) {
					if (strcmp(action, "DOCK_LEFT") == 0) {
						toplevel->docked_side = 1;
						wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 1280, 720);
						// Keep at least 1 pixel on output so app doesn't suspend!
						wlr_scene_node_set_position(&toplevel->scene_tree->node, out_w - 1, out_h - 1); 
						wlr_scene_node_lower_to_bottom(&toplevel->scene_tree->node);
						wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, false);
                        wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
					} else if (strcmp(action, "DOCK_RIGHT") == 0) {
						toplevel->docked_side = 2;
						wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 1280, 720);
						wlr_scene_node_set_position(&toplevel->scene_tree->node, out_w - 1, out_h - 1);
						wlr_scene_node_lower_to_bottom(&toplevel->scene_tree->node);
						wlr_xdg_toplevel_set_activated(toplevel->xdg_toplevel, false);
                        wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
					} else if (strcmp(action, "UNDOCK") == 0) {
						toplevel->docked_side = 0;
						if (toplevel->maximized) {
							wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
							wlr_scene_node_set_position(&toplevel->scene_tree->node, 0, 0);
						} else {
							wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 800, 600);
							wlr_scene_node_set_position(&toplevel->scene_tree->node, 560, 240); // Restore
						}
						wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
						focus_toplevel(toplevel);
                        wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
					} else if (strcmp(action, "MAXIMIZE") == 0) {
						if (!toplevel->maximized) {
							toplevel->saved_x = toplevel->scene_tree->node.x;
							toplevel->saved_y = toplevel->scene_tree->node.y;
							toplevel->saved_geometry.width = toplevel->xdg_toplevel->base->geometry.width;
							if (toplevel->saved_geometry.width == 0) toplevel->saved_geometry.width = 800;
							toplevel->saved_geometry.height = toplevel->xdg_toplevel->base->geometry.height;
							if (toplevel->saved_geometry.height == 0) toplevel->saved_geometry.height = 600;

							wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
							wlr_scene_node_set_position(&toplevel->scene_tree->node, 0, 0);
							wlr_xdg_toplevel_set_maximized(toplevel->xdg_toplevel, true);
							toplevel->maximized = true;
							wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
							focus_toplevel(toplevel);
                            wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
						}
					} else if (strcmp(action, "RESTORE") == 0) {
						if (toplevel->maximized) {
							wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, toplevel->saved_geometry.width, toplevel->saved_geometry.height);
							wlr_scene_node_set_position(&toplevel->scene_tree->node, toplevel->saved_x, toplevel->saved_y);
							wlr_xdg_toplevel_set_maximized(toplevel->xdg_toplevel, false);
							toplevel->maximized = false;
							wlr_scene_node_raise_to_top(&toplevel->scene_tree->node);
							focus_toplevel(toplevel);
                            wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
						}
					} else if (strcmp(action, "CLOSE") == 0) {
						wlr_xdg_toplevel_send_close(toplevel->xdg_toplevel);
					}
					update_workspace_state(server);
					break;
				}
			}
		}
		fclose(f);
		remove("/tmp/dock_action.txt");
	}
	wl_event_source_timer_update(server->dock_ipc_timer, 100);
	return 0;
}

static void xdg_toplevel_map(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, map);
	wl_list_insert(&toplevel->server->toplevels, &toplevel->link);
	toplevel->docked_side = 0; 

	const char *app_id = toplevel->xdg_toplevel->app_id;
	if (app_id != NULL && strstr(app_id, "workspace") != NULL) {
		// DYNAMIC OUTPUT RESOLUTION ALLOCATION HERE
		struct wlr_box box;
		wlr_output_layout_get_box(toplevel->server->output_layout, NULL, &box);
		int out_w = box.width > 0 ? box.width : 1920;
		int out_h = box.height > 0 ? box.height : 1080;
		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
		wlr_scene_node_set_position(&toplevel->scene_tree->node, 0, 0);
		focus_toplevel(toplevel);
		return; 
	}

	wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 800, 600);
	wlr_scene_node_set_position(&toplevel->scene_tree->node, 560, 240); 
	focus_toplevel(toplevel);
	update_workspace_state(toplevel->server);
}

static void xdg_toplevel_unmap(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, unmap);
	if (toplevel == toplevel->server->grabbed_toplevel) {
		reset_cursor_mode(toplevel->server);
	}
    
	if (toplevel->docked_side != 0) {
		char filename[64];
		snprintf(filename, sizeof(filename), "/tmp/thumb_%p.rgba", (void*)toplevel);
		remove(filename);
	}
    
	wl_list_remove(&toplevel->link);
	update_workspace_state(toplevel->server);
}

// --- ROBUST THUMBNAIL EXTRACTOR (Fixed Stride + Atomic Writes) ---
static void update_thumbnail(struct tinywl_toplevel *toplevel) {
	if (toplevel->docked_side == 0) return;

	struct wlr_surface *surface = toplevel->xdg_toplevel->base->surface;
	if (!surface || !surface->buffer) return;

	struct wlr_buffer *buffer = &surface->buffer->base;
	
	void *data;
	uint32_t format;
	size_t stride;

	if (wlr_buffer_begin_data_ptr_access(buffer, WLR_BUFFER_DATA_PTR_ACCESS_READ, &data, &format, &stride)) {
		int src_width = buffer->width;
		int src_height = buffer->height;
		int dst_width = 290;
		int dst_height = 200;
        
		if (stride >= src_width * 4) {
			char tmp_filename[64];
			char filename[64];
			snprintf(tmp_filename, sizeof(tmp_filename), "/tmp/thumb_%p.tmp", (void*)toplevel);
			snprintf(filename, sizeof(filename), "/tmp/thumb_%p.rgba", (void*)toplevel);
            
			// 1. Write to a temporary file first (ATOMIC WRITE)
			FILE *f = fopen(tmp_filename, "wb");
			if (f) {
				// Treat source as raw bytes so stride math is flawless
				uint8_t *src8 = (uint8_t *)data;
				uint32_t *dst32 = malloc(dst_width * dst_height * 4);
                
				if (dst32) {
					for (int y = 0; y < dst_height; y++) {
						int src_y = y * src_height / dst_height;
						uint32_t *dst_row = dst32 + (y * dst_width);
						
						// Step exactly 'stride' bytes per row to prevent diagonal glitches
						uint8_t *src_row = src8 + (src_y * stride); 
						
						for (int x = 0; x < dst_width; x++) {
							int src_x = x * src_width / dst_width;
							// Extract the specific 32-bit pixel safely
							dst_row[x] = *(uint32_t*)(src_row + (src_x * 4)); 
						}
					}
					fwrite(dst32, 1, dst_width * dst_height * 4, f);
					free(dst32);
				}
				fclose(f);
				
				// 2. Rename is atomic. Flutter will NEVER read a half-written file!
				rename(tmp_filename, filename); 
			}
		}
		wlr_buffer_end_data_ptr_access(buffer);
	}
}

static void xdg_toplevel_commit(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, commit);
	if (toplevel->xdg_toplevel->base->initial_commit) {
		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, 0, 0);
	}
    
	if (toplevel->docked_side != 0) {
		update_thumbnail(toplevel);
	}
}

static void xdg_toplevel_destroy(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, destroy);
	wl_list_remove(&toplevel->map.link);
	wl_list_remove(&toplevel->unmap.link);
	wl_list_remove(&toplevel->commit.link);
	wl_list_remove(&toplevel->destroy.link);
	wl_list_remove(&toplevel->request_move.link);
	wl_list_remove(&toplevel->request_resize.link);
	wl_list_remove(&toplevel->request_maximize.link);
	wl_list_remove(&toplevel->request_fullscreen.link);
	free(toplevel);
}

static void begin_interactive(struct tinywl_toplevel *toplevel, enum tinywl_cursor_mode mode, uint32_t edges) {
	struct tinywl_server *server = toplevel->server;
	server->grabbed_toplevel = toplevel;
	server->cursor_mode = mode;

	if (mode == TINYWL_CURSOR_MOVE) {
		server->grab_x = server->cursor->x - toplevel->scene_tree->node.x;
		server->grab_y = server->cursor->y - toplevel->scene_tree->node.y;
	} else {
		struct wlr_box *geo_box = &toplevel->xdg_toplevel->base->geometry;
		double border_x = (toplevel->scene_tree->node.x + geo_box->x) +
			((edges & WLR_EDGE_RIGHT) ? geo_box->width : 0);
		double border_y = (toplevel->scene_tree->node.y + geo_box->y) +
			((edges & WLR_EDGE_BOTTOM) ? geo_box->height : 0);
		server->grab_x = server->cursor->x - border_x;
		server->grab_y = server->cursor->y - border_y;

		server->grab_geobox = *geo_box;
		server->grab_geobox.x += toplevel->scene_tree->node.x;
		server->grab_geobox.y += toplevel->scene_tree->node.y;
		server->resize_edges = edges;
	}
}

static void xdg_toplevel_request_move(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, request_move);
	if (toplevel->xdg_toplevel->app_id != NULL && strstr(toplevel->xdg_toplevel->app_id, "workspace") != NULL) {
		return; 
	}
	begin_interactive(toplevel, TINYWL_CURSOR_MOVE, 0);
}

static void xdg_toplevel_request_resize(struct wl_listener *listener, void *data) {
	struct wlr_xdg_toplevel_resize_event *event = data;
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, request_resize);
	if (toplevel->xdg_toplevel->app_id != NULL && strstr(toplevel->xdg_toplevel->app_id, "workspace") != NULL) {
		return; 
	}
	begin_interactive(toplevel, TINYWL_CURSOR_RESIZE, event->edges);
}

static void xdg_toplevel_request_maximize(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, request_maximize);
	
	// CRITICAL FIX: Ignore maximize requests if the surface isn't fully initialized yet.
	// Apps (especially GTK) requesting this on launch will crash wlroots otherwise.
	if (!toplevel->xdg_toplevel->base->initialized) {
		return;
	}

	// Native maximize via double-click titlebar/app request
	bool maximize = toplevel->xdg_toplevel->requested.maximized;
	if (maximize == toplevel->maximized) return;

	if (maximize) {
		struct wlr_box box;
		wlr_output_layout_get_box(toplevel->server->output_layout, NULL, &box);
		int out_w = box.width > 0 ? box.width : 1920;
		int out_h = box.height > 0 ? box.height : 1080;

		toplevel->saved_x = toplevel->scene_tree->node.x;
		toplevel->saved_y = toplevel->scene_tree->node.y;
		toplevel->saved_geometry.width = toplevel->xdg_toplevel->base->geometry.width;
		if (toplevel->saved_geometry.width == 0) toplevel->saved_geometry.width = 800;
		toplevel->saved_geometry.height = toplevel->xdg_toplevel->base->geometry.height;
		if (toplevel->saved_geometry.height == 0) toplevel->saved_geometry.height = 600;

		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
		wlr_scene_node_set_position(&toplevel->scene_tree->node, 0, 0);
		wlr_xdg_toplevel_set_maximized(toplevel->xdg_toplevel, true);
		toplevel->maximized = true;
	} else {
		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, toplevel->saved_geometry.width, toplevel->saved_geometry.height);
		wlr_scene_node_set_position(&toplevel->scene_tree->node, toplevel->saved_x, toplevel->saved_y);
		wlr_xdg_toplevel_set_maximized(toplevel->xdg_toplevel, false);
		toplevel->maximized = false;
	}
    
	wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
	update_workspace_state(toplevel->server);
}

static void xdg_toplevel_request_fullscreen(struct wl_listener *listener, void *data) {
	struct tinywl_toplevel *toplevel = wl_container_of(listener, toplevel, request_fullscreen);
	
	if (!toplevel->xdg_toplevel->base->initialized) {
		return;
	}

	bool fullscreen = toplevel->xdg_toplevel->requested.fullscreen;
	if (fullscreen) {
		struct wlr_box box;
		wlr_output_layout_get_box(toplevel->server->output_layout, NULL, &box);
		int out_w = box.width > 0 ? box.width : 1920;
		int out_h = box.height > 0 ? box.height : 1080;

		// Save current state to restore it later
		toplevel->saved_x = toplevel->scene_tree->node.x;
		toplevel->saved_y = toplevel->scene_tree->node.y;
		toplevel->saved_geometry.width = toplevel->xdg_toplevel->base->geometry.width;
		toplevel->saved_geometry.height = toplevel->xdg_toplevel->base->geometry.height;

		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, out_w, out_h);
		wlr_scene_node_set_position(&toplevel->scene_tree->node, 0, 0);
		wlr_xdg_toplevel_set_fullscreen(toplevel->xdg_toplevel, true);
	} else {
		// Restore geometry when leaving fullscreen
		int width = toplevel->saved_geometry.width > 0 ? toplevel->saved_geometry.width : 800;
		int height = toplevel->saved_geometry.height > 0 ? toplevel->saved_geometry.height : 600;

		wlr_xdg_toplevel_set_size(toplevel->xdg_toplevel, width, height);
		wlr_scene_node_set_position(&toplevel->scene_tree->node, toplevel->saved_x, toplevel->saved_y);
		wlr_xdg_toplevel_set_fullscreen(toplevel->xdg_toplevel, false);
	}
	wlr_xdg_surface_schedule_configure(toplevel->xdg_toplevel->base);
}

static void server_new_xdg_toplevel(struct wl_listener *listener, void *data) {
	struct tinywl_server *server = wl_container_of(listener, server, new_xdg_toplevel);
	struct wlr_xdg_toplevel *xdg_toplevel = data;

	struct tinywl_toplevel *toplevel = calloc(1, sizeof(*toplevel));
	toplevel->server = server;
	toplevel->xdg_toplevel = xdg_toplevel;
	toplevel->scene_tree = wlr_scene_xdg_surface_create(&toplevel->server->scene->tree, xdg_toplevel->base);
	toplevel->scene_tree->node.data = toplevel;
	xdg_toplevel->base->data = toplevel->scene_tree;

	toplevel->map.notify = xdg_toplevel_map;
	wl_signal_add(&xdg_toplevel->base->surface->events.map, &toplevel->map);
	toplevel->unmap.notify = xdg_toplevel_unmap;
	wl_signal_add(&xdg_toplevel->base->surface->events.unmap, &toplevel->unmap);
	toplevel->commit.notify = xdg_toplevel_commit;
	wl_signal_add(&xdg_toplevel->base->surface->events.commit, &toplevel->commit);
	toplevel->destroy.notify = xdg_toplevel_destroy;
	wl_signal_add(&xdg_toplevel->events.destroy, &toplevel->destroy);

	toplevel->request_move.notify = xdg_toplevel_request_move;
	wl_signal_add(&xdg_toplevel->events.request_move, &toplevel->request_move);
	toplevel->request_resize.notify = xdg_toplevel_request_resize;
	wl_signal_add(&xdg_toplevel->events.request_resize, &toplevel->request_resize);
	toplevel->request_maximize.notify = xdg_toplevel_request_maximize;
	wl_signal_add(&xdg_toplevel->events.request_maximize, &toplevel->request_maximize);
	toplevel->request_fullscreen.notify = xdg_toplevel_request_fullscreen;
	wl_signal_add(&xdg_toplevel->events.request_fullscreen, &toplevel->request_fullscreen);
}

static void xdg_popup_commit(struct wl_listener *listener, void *data) {
	struct tinywl_popup *popup = wl_container_of(listener, popup, commit);
	if (popup->xdg_popup->base->initial_commit) {
		wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
	}
}

static void xdg_popup_destroy(struct wl_listener *listener, void *data) {
	struct tinywl_popup *popup = wl_container_of(listener, popup, destroy);
	wl_list_remove(&popup->commit.link);
	wl_list_remove(&popup->destroy.link);
	free(popup);
}

static void server_new_xdg_popup(struct wl_listener *listener, void *data) {
	struct wlr_xdg_popup *xdg_popup = data;
	struct tinywl_popup *popup = calloc(1, sizeof(*popup));
	popup->xdg_popup = xdg_popup;

	struct wlr_xdg_surface *parent = wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
	assert(parent != NULL);
	struct wlr_scene_tree *parent_tree = parent->data;
	xdg_popup->base->data = wlr_scene_xdg_surface_create(parent_tree, xdg_popup->base);

	popup->commit.notify = xdg_popup_commit;
	wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);
	popup->destroy.notify = xdg_popup_destroy;
	wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);
}

int main(int argc, char *argv[]) {
	wlr_log_init(WLR_DEBUG, NULL);
	char *startup_cmd = NULL;
	int c;
	while ((c = getopt(argc, argv, "s:h")) != -1) {
		switch (c) {
		case 's':
			startup_cmd = optarg;
			break;
		default:
			printf("Usage: %s [-s startup command]\n", argv[0]);
			return 0;
		}
	}

	struct tinywl_server server = {0};
	server.wl_display = wl_display_create();
	server.backend = wlr_backend_autocreate(wl_display_get_event_loop(server.wl_display), NULL);
	if (server.backend == NULL) {
		wlr_log(WLR_ERROR, "failed to create wlr_backend");
		return 1;
	}

	server.renderer = wlr_renderer_autocreate(server.backend);
	if (server.renderer == NULL) {
		wlr_log(WLR_ERROR, "failed to create wlr_renderer");
		return 1;
	}

	wlr_renderer_init_wl_display(server.renderer, server.wl_display);

	server.allocator = wlr_allocator_autocreate(server.backend, server.renderer);
	if (server.allocator == NULL) {
		wlr_log(WLR_ERROR, "failed to create wlr_allocator");
		return 1;
	}

	wlr_compositor_create(server.wl_display, 5, server.renderer);
	wlr_subcompositor_create(server.wl_display);
	wlr_data_device_manager_create(server.wl_display);

	server.output_layout = wlr_output_layout_create(server.wl_display);
	
	// --- BIND THE LAYOUT RESIZE LISTENER ---
	server.layout_change.notify = server_layout_change;
	wl_signal_add(&server.output_layout->events.change, &server.layout_change);

	wl_list_init(&server.outputs);
	server.new_output.notify = server_new_output;
	wl_signal_add(&server.backend->events.new_output, &server.new_output);

	server.scene = wlr_scene_create();
	server.scene_layout = wlr_scene_attach_output_layout(server.scene, server.output_layout);

	wl_list_init(&server.toplevels);
	server.xdg_shell = wlr_xdg_shell_create(server.wl_display, 3);
	server.new_xdg_toplevel.notify = server_new_xdg_toplevel;
	wl_signal_add(&server.xdg_shell->events.new_toplevel, &server.new_xdg_toplevel);
	server.new_xdg_popup.notify = server_new_xdg_popup;
	wl_signal_add(&server.xdg_shell->events.new_popup, &server.new_xdg_popup);

	server.cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(server.cursor, server.output_layout);
	server.cursor_mgr = wlr_xcursor_manager_create(NULL, 24);

	server.cursor_mode = TINYWL_CURSOR_PASSTHROUGH;
	server.cursor_motion.notify = server_cursor_motion;
	wl_signal_add(&server.cursor->events.motion, &server.cursor_motion);
	server.cursor_motion_absolute.notify = server_cursor_motion_absolute;
	wl_signal_add(&server.cursor->events.motion_absolute, &server.cursor_motion_absolute);
	server.cursor_button.notify = server_cursor_button;
	wl_signal_add(&server.cursor->events.button, &server.cursor_button);
	server.cursor_axis.notify = server_cursor_axis;
	wl_signal_add(&server.cursor->events.axis, &server.cursor_axis);
	server.cursor_frame.notify = server_cursor_frame;
	wl_signal_add(&server.cursor->events.frame, &server.cursor_frame);

	wl_list_init(&server.keyboards);
	server.new_input.notify = server_new_input;
	wl_signal_add(&server.backend->events.new_input, &server.new_input);
	server.seat = wlr_seat_create(server.wl_display, "seat0");
	server.request_cursor.notify = seat_request_cursor;
	wl_signal_add(&server.seat->events.request_set_cursor, &server.request_cursor);
	server.request_set_selection.notify = seat_request_set_selection;
	wl_signal_add(&server.seat->events.request_set_selection, &server.request_set_selection);

	const char *socket = wl_display_add_socket_auto(server.wl_display);
	if (!socket) {
		wlr_backend_destroy(server.backend);
		return 1;
	}

	if (!wlr_backend_start(server.backend)) {
		wlr_backend_destroy(server.backend);
		wl_display_destroy(server.wl_display);
		return 1;
	}

	// --- INIT OUR CUSTOM IPC EVENT TIMER FOR DOCK/UNDOCK ---
	server.dock_ipc_timer = wl_event_loop_add_timer(wl_display_get_event_loop(server.wl_display), handle_dock_ipc, &server);
	wl_event_source_timer_update(server.dock_ipc_timer, 100);

	// --- CLEANUP PREVIOUS CRASH/SHUTDOWN STATE ---
	system("rm -f /tmp/thumb_*.rgba /tmp/thumb_*.tmp /tmp/dock_action.txt"); 
	update_workspace_state(&server); 

	setenv("WAYLAND_DISPLAY", socket, true);
	if (startup_cmd) {
		if (fork() == 0) {
			execl("/bin/sh", "/bin/sh", "-c", startup_cmd, (void *)NULL);
		}
	}
	wlr_log(WLR_INFO, "Running Wayland compositor on WAYLAND_DISPLAY=%s", socket);
	wl_display_run(server.wl_display);

	wl_display_destroy_clients(server.wl_display);
	wl_list_remove(&server.new_xdg_toplevel.link);
	wl_list_remove(&server.new_xdg_popup.link);
	wl_list_remove(&server.cursor_motion.link);
	wl_list_remove(&server.cursor_motion_absolute.link);
	wl_list_remove(&server.cursor_button.link);
	wl_list_remove(&server.cursor_axis.link);
	wl_list_remove(&server.cursor_frame.link);
	wl_list_remove(&server.new_input.link);
	wl_list_remove(&server.request_cursor.link);
	wl_list_remove(&server.request_set_selection.link);
	wl_list_remove(&server.new_output.link);
	wl_list_remove(&server.layout_change.link); // Clean up custom layout listener

	wlr_scene_node_destroy(&server.scene->tree.node);
	wlr_xcursor_manager_destroy(server.cursor_mgr);
	wlr_cursor_destroy(server.cursor);
	wlr_allocator_destroy(server.allocator);
	wlr_renderer_destroy(server.renderer);
	wlr_backend_destroy(server.backend);
	wl_display_destroy(server.wl_display);
	return 0;
}