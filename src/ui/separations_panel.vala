using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class SeparationsPanel : Panel {
        private Label readout;

        public SeparationsPanel (PublishWindow win) {
            base (win);
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            var c = win.canvas;
            var g = group (_("Separations Preview"), _("Shows each ink plate on screen, with overprint simulated as on press"));
            var on = new SwitchRow (_("Preview Separations"), null, c.separations);
            on.switch_btn.notify["active"].connect (() => {
                c.separations = on.switch_btn.active;
                if (c.separations && c.sep_enabled.size == 0) c.sep_enabled.add_all (PrepressExport.plates (pub));
                c.drop_separations ();
                c.queue_draw ();
            });
            g.add_row (on);
            var plates = PrepressExport.plates (pub);
            var pg = group (_("Inks"), ngettext ("%d plate", "%d plates", plates.size).printf (plates.size));
            foreach (string pl in plates) {
                string name = pl;
                var row = new SwitchRow (name, null, c.sep_enabled.size == 0 || c.sep_enabled.contains (name));
                row.switch_btn.notify["active"].connect (() => {
                    if (c.sep_enabled.size == 0) c.sep_enabled.add_all (plates);
                    if (row.switch_btn.active) c.sep_enabled.add (name);
                    else c.sep_enabled.remove (name);
                    c.queue_draw ();
                });
                pg.add_row (row);
            }
            var ig = group (_("Ink Coverage"), _("Move the pointer over the page while the preview is on"));
            readout = new Label (_("No reading yet"));
            readout.xalign = 0;
            readout.wrap = true;
            readout.margin_start = readout.margin_end = 12;
            readout.margin_top = readout.margin_bottom = 8;
            ig.add_row (readout);
        }

        public void show_ink (int page, double x, double y) {
            if (readout == null || !win.canvas.separations) return;
            var sp = win.canvas.separation_for (page);
            if (sp == null) return;
            var sb = new StringBuilder ();
            double total = 0;
            foreach (var e in sp.ink_at (x, y).entries) {
                if (e.value < 0.5) continue;
                sb.append ("%s %d%%\n".printf (e.key, (int) Math.round (e.value)));
                total += e.value;
            }
            sb.append (_("Total %d%%").printf ((int) Math.round (total)));
            readout.label = sb.str;
        }
    }
}
