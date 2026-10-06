using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class StoryEditor : AppDialog {
        private PublishWindow win;
        private Story story;
        private TextView view;
        private DrawingArea gutter;
        private Label status;
        private TextTag overset_tag;
        private bool loading = false;
        private uint refresh_id = 0;

        public StoryEditor (PublishWindow win, Story story) {
            base ((Gtk.Application) win.application, false, true);
            this.win = win;
            this.story = story;
            set_title (_("Story Editor"));
            transient_for = win;
            set_default_size (720, 640);
            add_css_class ("publish-story-editor");
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_start = box.margin_end = 16;
            box.margin_bottom = 16;
            status = new Label ("");
            status.xalign = 0;
            status.add_css_class ("caption");
            status.add_css_class ("dim-label");
            box.append (status);
            view = new TextView ();
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.top_margin = 8;
            view.bottom_margin = 8;
            view.left_margin = 8;
            view.right_margin = 8;
            view.pixels_below_lines = 6;
            gutter = new DrawingArea ();
            gutter.set_size_request (132, -1);
            gutter.set_draw_func (draw_gutter);
            gutter.add_css_class ("publish-style-gutter");
            view.set_gutter (TextWindowType.LEFT, gutter);
            overset_tag = view.buffer.create_tag ("overset", "background", "rgba(220,40,40,0.18)", null);
            var scroll = new ScrolledWindow ();
            scroll.child = view;
            scroll.vexpand = true;
            scroll.vadjustment.value_changed.connect (() => gutter.queue_draw ());
            var frame = new Frame (null);
            frame.child = scroll;
            box.append (frame);
            content_box.append (box);
            load ();
            view.buffer.insert_text.connect (on_insert);
            view.buffer.delete_range.connect (on_delete);
            view.buffer.changed.connect (() => gutter.queue_draw ());
            Singularity.Text.SpellIntegration.attach (view);
            win.doc.replaced.connect (on_replaced);
            close_request.connect (() => {
                if (win.doc != null) win.doc.replaced.disconnect (on_replaced);
                return false;
            });
        }

        private void on_replaced () {
            var s = win.doc.pub.stories.has_key (story.id) ? win.doc.pub.stories[story.id] : null;
            if (s == null) {
                close ();
                return;
            }
            story = s;
            load ();
        }

        private void load () {
            loading = true;
            view.buffer.text = story.plain_text ().replace (OBJ_STR, "•");
            loading = false;
            update_status ();
        }

        private void on_insert (ref TextIter pos, string text, int len) {
            if (loading) return;
            int off = pos.get_offset ();
            win.doc.checkpoint (_("Edit Story"), "story:%d".printf (story.id));
            var tp = story.from_linear (off);
            story.insert_text (tp, text);
            changed_story ();
        }

        private void on_delete (TextIter a, TextIter b) {
            if (loading) return;
            int oa = a.get_offset (), ob = b.get_offset ();
            if (oa == ob) return;
            win.doc.checkpoint (_("Edit Story"), "story:%d".printf (story.id));
            story.delete_range (story.from_linear (oa), story.from_linear (ob));
            changed_story ();
        }

        private void changed_story () {
            win.doc.touch ();
            win.canvas.cache.invalidate_story (story.id);
            win.canvas.queue_draw ();
            if (refresh_id != 0) Source.remove (refresh_id);
            refresh_id = Timeout.add (250, () => {
                refresh_id = 0;
                update_status ();
                win.content_edited ();
                return Source.REMOVE;
            });
        }

        private void update_status () {
            var res = win.canvas.cache.story (story.id);
            int words = 0;
            foreach (string w in story.plain_text ().split_set (" \n\t")) if (w.strip () != "") words++;
            string s = ngettext ("%d word", "%d words", words).printf (words) + ", " + ngettext ("%d paragraph", "%d paragraphs", story.paras.size).printf (story.paras.size) + ", " + ngettext ("%d frame", "%d frames", story.frames.size).printf (story.frames.size);
            TextIter start, end;
            view.buffer.get_bounds (out start, out end);
            view.buffer.remove_tag (overset_tag, start, end);
            if (res.overset) {
                s += ", " + ngettext ("%d character overset", "%d characters overset", res.overset_chars).printf (res.overset_chars);
                TextIter from;
                view.buffer.get_iter_at_offset (out from, story.linear (res.overset_at));
                view.buffer.apply_tag (overset_tag, from, end);
            }
            status.label = s;
            gutter.queue_draw ();
        }

        private void draw_gutter (DrawingArea da, Cairo.Context cr, int w, int h) {
            var fg = da.get_color ();
            var layout = da.create_pango_layout ("");
            layout.set_width ((w - 12) * Pango.SCALE);
            layout.set_ellipsize (Pango.EllipsizeMode.END);
            var buf = view.buffer;
            for (int i = 0; i < story.paras.size && i < buf.get_line_count (); i++) {
                TextIter it;
                buf.get_iter_at_line (out it, i);
                int y, lh;
                view.get_line_yrange (it, out y, out lh);
                int wx, wy;
                view.buffer_to_window_coords (TextWindowType.LEFT, 0, y, out wx, out wy);
                if (wy + lh < 0 || wy > h) continue;
                layout.set_text (story.paras[i].style, -1);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
                cr.move_to (6, wy + view.top_margin * 0);
                Pango.cairo_show_layout (cr, layout);
            }
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.15);
            cr.rectangle (w - 1, 0, 1, h);
            cr.fill ();
        }
    }
}
