using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class TypographyDialogs {
        private static SpinRow spin (PreferencesGroup g, string title, double min, double max, double step, double value, int digits = 0) {
            var r = new SpinRow (title, null, min, max, step, value);
            r.spin_btn.digits = digits;
            g.add_row (r);
            return r;
        }

        public static void install (PublishWindow w) {
            w.doc_action ("justification", () => justification (w));
            w.doc_action ("hyphenation-settings", () => hyphenation (w));
            w.doc_action ("hyphenation-exceptions", () => exceptions (w));
            w.doc_action ("text-variables", () => variables (w));
            w.doc_action ("anchored-options", () => anchored (w));
            w.doc_action ("table-continue", () => table_continue (w));
            w.doc_action ("table-flow-options", () => table_options (w));
            w.doc_action ("toc", () => toc (w));
            w.doc_action ("toc-update", () => toc_update (w));
            w.doc_action ("insert-footnote", () => {
                if (w.canvas.edit == null) {
                    w.toast (_("Click in the text where the footnote reference goes"));
                    return;
                }
                var run = w.canvas.insert_footnote ();
                if (run != null) edit_note (w, run, true);
            });
            w.doc_action ("edit-footnote", () => {
                var e = w.canvas.edit;
                Run? run = e != null ? e.story.note_near (e.caret) : null;
                if (run == null) {
                    w.toast (_("Place the text cursor next to a footnote reference"));
                    return;
                }
                edit_note (w, run, false);
            });
            w.doc_action ("footnote-options", () => footnote_options (w));
            w.doc_action ("insert-cross-reference", () => cross_reference (w));
            w.doc_action ("text-anchor", () => text_anchor (w));
            w.doc_action ("index-entry", () => index_entry (w));
            w.doc_action ("style-rules", () => style_rules (w, null));
            w.doc_action ("conditions", () => conditions (w));
            w.doc_action ("generate-index", () => generate_index (w));
            w.doc_action ("insert-endnote", () => {
                var e = w.canvas.edit;
                if (e == null) {
                    w.toast (_("Click in the text where the endnote reference goes"));
                    return;
                }
                w.doc.checkpoint (_("Insert Endnote"));
                var run = Footnotes.make_endnote (w.doc.pub, "");
                var pos = e.story.insert_run (e.caret, run);
                e.collapse (pos);
                w.doc.touch ();
                w.canvas.text_edited ();
                edit_note (w, run, true);
            });
            w.doc_action ("update-endnotes", () => {
                int n = 0;
                w.edit (_("Update Endnotes"), () => n = Footnotes.update_endnotes (w.doc.pub, _("Notes")));
                w.canvas.relayout ();
                w.pages_panel.load ();
                w.toast (ngettext ("%d endnote collected at the end of the publication", "%d endnotes collected at the end of the publication", n).printf (n));
            });
        }

        public static void justification (PublishWindow w) {
            var pf = w.current_para_format ();
            var dlg = Dialogs.make (w, _("Justification"), 520, 640);
            var box = Dialogs.body (dlg);
            var cg = new PreferencesGroup (_("Composer"), _("The paragraph composer weighs every line of the paragraph together; the single-line composer fills one line at a time"));
            string[] comps = { _("Paragraph Composer"), _("Single-line Composer") };
            var comp = new SelectionRow (_("Composer"), comps, comps[pf.composer == 1 ? 1 : 0]);
            cg.add_row (comp);
            box.append (cg);
            var wg = new PreferencesGroup (_("Word Spacing"), _("Percent of the normal space"));
            var wmin = spin (wg, _("Minimum"), 0, 1000, 1, pf.word_min);
            var wopt = spin (wg, _("Desired"), 0, 1000, 1, pf.word_opt);
            var wmax = spin (wg, _("Maximum"), 0, 1000, 1, pf.word_max);
            box.append (wg);
            var lg = new PreferencesGroup (_("Letter Spacing"), _("Percent of the normal space, added between letters"));
            var lmin = spin (lg, _("Minimum"), -100, 500, 1, pf.letter_min);
            var lopt = spin (lg, _("Desired"), -100, 500, 1, pf.letter_opt);
            var lmax = spin (lg, _("Maximum"), -100, 500, 1, pf.letter_max);
            box.append (lg);
            var gg = new PreferencesGroup (_("Glyph Scaling"), _("Percent of the normal glyph width"));
            var gmin = spin (gg, _("Minimum"), 50, 200, 1, pf.glyph_min);
            var gopt = spin (gg, _("Desired"), 50, 200, 1, pf.glyph_opt);
            var gmax = spin (gg, _("Maximum"), 50, 200, 1, pf.glyph_max);
            box.append (gg);
            Dialogs.footer (dlg, _("Apply"), () => {
                double a = wmin.spin_btn.value, b = wopt.spin_btn.value, c = wmax.spin_btn.value;
                double d = lmin.spin_btn.value, e = lopt.spin_btn.value, f = lmax.spin_btn.value;
                double g1 = gmin.spin_btn.value, g2 = gopt.spin_btn.value, g3 = gmax.spin_btn.value;
                if (a > b || b > c || d > e || e > f || g1 > g2 || g2 > g3) {
                    w.show_error (_("Check the Values"), _("Each minimum must not be larger than the desired value, and the desired value must not be larger than the maximum."));
                    return;
                }
                int composer = comp.current_value == comps[1] ? 1 : 0;
                w.format_paras (_("Justification"), (p) => {
                    p.fmt.composer = composer;
                    p.fmt.word_min = a;
                    p.fmt.word_opt = b;
                    p.fmt.word_max = c;
                    p.fmt.letter_min = d;
                    p.fmt.letter_opt = e;
                    p.fmt.letter_max = f;
                    p.fmt.glyph_min = g1;
                    p.fmt.glyph_opt = g2;
                    p.fmt.glyph_max = g3;
                });
            });
            dlg.open_dialog ();
        }

        public static void hyphenation (PublishWindow w) {
            var pf = w.current_para_format ();
            var dlg = Dialogs.make (w, _("Hyphenation"), 480, 600);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Hyphenation"), _("Where words may break at the end of a line"));
            var on = new SwitchRow (_("Hyphenate"), null, pf.hyphenate == 1);
            g.add_row (on);
            var minw = spin (g, _("Words with at Least (letters)"), 2, 25, 1, pf.hyph_min_word);
            var before = spin (g, _("After First (letters)"), 1, 15, 1, pf.hyph_before);
            var after = spin (g, _("Before Last (letters)"), 1, 15, 1, pf.hyph_after);
            var limit = spin (g, _("Hyphen Limit (lines in a row)"), 0, 25, 1, pf.hyph_limit);
            var zone = spin (g, _("Hyphenation Zone (pt)"), 0, 720, 1, pf.hyph_zone, 1);
            zone.subtitle = _("Used for text that is not justified: no break inside the zone at the end of the line");
            var caps = new SwitchRow (_("Hyphenate Capitalized Words"), null, pf.hyph_caps != 0);
            g.add_row (caps);
            box.append (g);
            var eg = new PreferencesGroup (_("Exceptions"), _("Words with a fixed hyphenation for this publication"));
            var er = new ActionRow (_("Hyphenation Exceptions"), ngettext ("%d word", "%d words", w.doc.pub.hyph_exceptions.size).printf (w.doc.pub.hyph_exceptions.size));
            var eb = new Button.with_label (_("Edit…"));
            eb.valign = Align.CENTER;
            eb.clicked.connect (() => {
                dlg.close ();
                exceptions (w);
            });
            er.add_suffix (eb);
            eg.add_row (er);
            box.append (eg);
            Dialogs.footer (dlg, _("Apply"), () => {
                int h = on.switch_btn.active ? 1 : 0;
                int mw = (int) minw.spin_btn.value, bf = (int) before.spin_btn.value, af = (int) after.spin_btn.value, lm = (int) limit.spin_btn.value;
                double zn = zone.spin_btn.value;
                int cp = caps.switch_btn.active ? 1 : 0;
                w.format_paras (_("Hyphenation"), (p) => {
                    p.fmt.hyphenate = h;
                    p.fmt.hyph_min_word = mw;
                    p.fmt.hyph_before = bf;
                    p.fmt.hyph_after = af;
                    p.fmt.hyph_limit = lm;
                    p.fmt.hyph_zone = zn;
                    p.fmt.hyph_caps = cp;
                });
            });
            dlg.open_dialog ();
        }

        public static void exceptions (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Hyphenation Exceptions"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Words"), _("Write the word with a hyphen at each place it may break, for example type-set-ting; a word without hyphens is never broken"));
            var entry = new EntryRow (_("Add a Word"));
            g.add_row (entry);
            box.append (g);
            var lg = new PreferencesGroup (_("In This Publication"));
            box.append (lg);
            var rows = new Gee.ArrayList<Widget> ();
            ProDialogs.Done? refresh = null;
            refresh = () => {
                foreach (var r in rows) lg.remove_row (r);
                rows.clear ();
                foreach (var e in pub.hyph_exceptions.entries) {
                    string key = e.key;
                    var row = new ActionRow (e.value);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Remove");
                    del.clicked.connect (() => {
                        w.edit (_("Hyphenation Exceptions"), () => pub.hyph_exceptions.unset (key));
                        refresh ();
                    });
                    row.add_suffix (del);
                    lg.add_row (row);
                    rows.add (row);
                }
            };
            refresh ();
            var add = new Button.with_label (_("Add"));
            add.valign = Align.CENTER;
            entry.add_suffix (add);
            ProDialogs.Done commit = () => {
                string word = entry.text.strip ();
                if (word == "" || word.contains (" ")) return;
                string key = word.replace ("-", "").replace ("~", "").down ();
                w.edit (_("Hyphenation Exceptions"), () => pub.hyph_exceptions[key] = word.down ());
                entry.text = "";
                refresh ();
            };
            add.clicked.connect (() => commit ());
            entry.entry_activated.connect (() => commit ());
            Dialogs.footer (dlg, _("Done"), () => {});
            dlg.open_dialog ();
        }

        public static void new_tint (PublishWindow w) {
            var pub = w.doc.pub;
            string[] bases = {};
            foreach (var sw in pub.swatches) if (sw.tint_of == "" && sw.name != "Paper" && sw.name != "Registration") bases += sw.name;
            if (bases.length == 0) return;
            var dlg = Dialogs.make (w, _("New Tint Swatch"), 420, 360);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Tint"), _("A named tint follows its base colour when the base changes; spot tints print on the spot plate"));
            var base_row = new SelectionRow (_("Base Colour"), bases, bases[0]);
            g.add_row (base_row);
            var pct = new SpinRow (_("Tint (%)"), null, 1, 100, 5, 50);
            g.add_row (pct);
            box.append (g);
            Dialogs.footer (dlg, _("Add"), () => {
                string b = base_row.current_value;
                double t = pct.spin_btn.value;
                var src = pub.swatch (b);
                if (src == null) return;
                string nm = pub.unique_swatch_name ("%s %d%%".printf (b, (int) t));
                var sw = src.clone ();
                sw.name = nm;
                sw.tint_of = b;
                sw.tint = t;
                sw.spot = false;
                w.edit (_("New Tint Swatch"), () => pub.swatches.add (sw));
                w.swatches_panel.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void toc_update (PublishWindow w) {
            var pub = w.doc.pub;
            if (pub.toc == null || Toc.frame_of (pub, pub.toc.story) == null) {
                toc (w);
                return;
            }
            int n = 0;
            w.edit (_("Update Table of Contents"), () => n = Toc.update (pub, pub.toc));
            w.content_edited ();
            w.toast (ngettext ("Table of contents updated with %d entry", "Table of contents updated with %d entries", n).printf (n));
        }

        public static void toc (PublishWindow w) {
            var pub = w.doc.pub;
            var cur = pub.toc != null ? pub.toc.clone () : new TocSettings ();
            if (pub.toc == null) {
                cur.title = _("Contents");
                foreach (string h in new string[] { "Heading 1", "Heading 2" }) if (pub.styles.find_paragraph (h) != null) cur.levels.add (new TocLevel (h, h == "Heading 1" ? 1 : 2, ""));
            }
            var dlg = Dialogs.make (w, _("Table of Contents"), 500, 660);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Contents"));
            var title = new EntryRow (_("Title"));
            title.text = cur.title;
            g.add_row (title);
            var pn = new SwitchRow (_("Page Numbers"), _("After each entry, right aligned with a dot leader"), cur.page_numbers);
            g.add_row (pn);
            box.append (g);
            var lg = new PreferencesGroup (_("Paragraph Styles"), _("Paragraphs in these styles become entries; the level sets the indent"));
            var switches = new Gee.ArrayList<SwitchRow> ();
            var levels = new Gee.ArrayList<SpinRow> ();
            var names = new Gee.ArrayList<string> ();
            foreach (var st in pub.styles.paragraph) {
                if (st.name.has_prefix (_("TOC Level"))) continue;
                var existing = cur.level_for (st.name);
                var sw = new SwitchRow (st.name, null, existing != null);
                lg.add_row (sw);
                var lv = new SpinRow (_("Level"), null, 1, 9, 1, existing != null ? existing.level : 1);
                lv.visible = existing != null;
                sw.switch_btn.notify["active"].connect (() => lv.visible = sw.switch_btn.active);
                lg.add_row (lv);
                switches.add (sw);
                levels.add (lv);
                names.add (st.name);
            }
            box.append (lg);
            Dialogs.footer (dlg, pub.toc != null && Toc.frame_of (pub, pub.toc.story) != null ? _("Update") : _("Insert"), () => {
                var ns = new TocSettings ();
                ns.title = title.text.strip ();
                ns.page_numbers = pn.switch_btn.active;
                for (int k = 0; k < names.size; k++) if (switches[k].switch_btn.active) ns.levels.add (new TocLevel (names[k], (int) levels[k].spin_btn.value, ""));
                if (ns.levels.size == 0) {
                    w.show_error (_("Choose a Style"), _("Switch on at least one paragraph style to collect entries from."));
                    return;
                }
                int n = 0;
                w.canvas.end_edit ();
                w.edit (_("Table of Contents"), () => {
                    var frame = pub.toc != null ? Toc.frame_of (pub, pub.toc.story) : null;
                    if (frame == null) {
                        int page = int.max (0, w.doc.current_page);
                        var mr = pub.margin_rect (page);
                        frame = pub.add_text_frame (pub.pages[page].items, mr.x, mr.y, mr.w, mr.h);
                        frame.name = _("Table of Contents");
                    }
                    for (int k = 1; k <= 9; k++) foreach (var l in ns.levels) if (l.level == k) l.entry_style = Toc.entry_style_for (pub, k);
                    ns.story = frame.story;
                    pub.toc = ns;
                    n = Toc.update (pub, ns);
                });
                w.content_edited ();
                w.toast (ngettext ("Table of contents with %d entry", "Table of contents with %d entries", n).printf (n));
            });
            dlg.open_dialog ();
        }

        private static TableItem? selected_table (PublishWindow w) {
            if (w.canvas.edit != null && w.canvas.edit.table != null) return w.canvas.edit.table;
            var sel = w.sel ();
            if (sel.size == 1 && sel[0] is TableItem) return (TableItem) sel[0];
            return null;
        }

        private static string anchor_for (Publication pub, Paragraph p) {
            if (p.anchor != "") return p.anchor;
            int n = 1;
            var used = new Gee.HashSet<string> ();
            foreach (var st in pub.stories.values) foreach (var q in st.paras) if (q.anchor != "") used.add (q.anchor);
            while (used.contains ("ref-%d".printf (n))) n++;
            p.anchor = "ref-%d".printf (n);
            return p.anchor;
        }

        public static void cross_reference (PublishWindow w) {
            if (w.canvas.edit == null) {
                w.toast (_("Click in the text where the cross-reference goes"));
                return;
            }
            var pub = w.doc.pub;
            var targets = new Gee.ArrayList<Paragraph> ();
            string[] labels = {};
            foreach (var st in Footnotes.stories_in_order (pub)) {
                foreach (var p in st.paras) {
                    string t = p.text ().replace (OBJ_STR, "").strip ();
                    if ((t == "" && p.anchor == "") || targets.size >= 500) continue;
                    if (t.char_count () > 60) t = t.substring (0, t.index_of_nth_char (60)) + "…";
                    targets.add (p);
                    labels += p.anchor != "" ? "%s  (%s)".printf (t, p.anchor) : "%s  (%s)".printf (t, p.style);
                }
            }
            if (targets.size == 0) {
                w.toast (_("There is no paragraph to refer to yet"));
                return;
            }
            var dlg = Dialogs.make (w, _("Insert Cross-Reference"), 520, 420);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Destination"), _("The text and page number stay up to date when the destination moves"));
            var dest = new SelectionRow (_("Paragraph"), labels, labels[0]);
            g.add_row (dest);
            string[] formats = Fields.xref_formats ();
            var fmt = new SelectionRow (_("Format"), formats, formats[0]);
            g.add_row (fmt);
            box.append (g);
            Dialogs.footer (dlg, _("Insert"), () => {
                int di = 0, fi = 0;
                for (int i = 0; i < labels.length; i++) if (labels[i] == dest.current_value) di = i;
                for (int i = 0; i < formats.length; i++) if (formats[i] == fmt.current_value) fi = i;
                var target = targets[di];
                string name = "";
                w.edit (_("Text Anchor"), () => name = anchor_for (pub, target));
                w.canvas.insert_field (Fields.xref (fi, name));
            });
            dlg.open_dialog ();
        }

        public static void style_rules (PublishWindow w, string? style_name) {
            var pub = w.doc.pub;
            string target = style_name ?? "";
            if (target == "") {
                var para = w.current_paragraph ();
                target = para != null ? para.style : StyleSheet.BASIC;
            }
            var ps = pub.styles.find_paragraph (target) ?? pub.styles.find_paragraph (StyleSheet.BASIC);
            var nested = new Gee.ArrayList<NestedStyle> ();
            foreach (var n in ps.nested) nested.add (n.clone ());
            var greps = new Gee.ArrayList<GrepStyle> ();
            foreach (var g in ps.grep) greps.add (g.clone ());
            string[] cnames = {};
            foreach (var cs in pub.styles.character) cnames += cs.name;
            if (cnames.length == 0) {
                w.toast (_("Create a character style first; nested and GREP styles apply character styles"));
                return;
            }
            var dlg = Dialogs.make (w, _("Nested and GREP Styles"), 560, 680);
            var box = Dialogs.body (dlg);
            var ng = new PreferencesGroup (_("Nested Styles"), _("Applied in order from the start of every paragraph in “%s”").printf (ps.name));
            var gg = new PreferencesGroup (_("GREP Styles"), _("A character style for every match of a regular expression"));
            box.append (ng);
            box.append (gg);
            string[] units = NestedUnit.labels ();
            string[] modes = { _("Through"), _("Up To") };
            SourceFunc? refill = null;
            refill = () => {
                ng.clear ();
                gg.clear ();
                foreach (var n in nested) {
                    var cur = n;
                    var cs = new SelectionRow (_("Character Style"), cnames, cur.cstyle != "" ? cur.cstyle : cnames[0]);
                    if (cur.cstyle == "") cur.cstyle = cnames[0];
                    cs.selected.connect ((v) => cur.cstyle = v);
                    ng.add_row (cs);
                    var mode = new SelectionRow (_("Applies"), modes, modes[cur.through ? 0 : 1]);
                    mode.selected.connect ((v) => cur.through = v == modes[0]);
                    ng.add_row (mode);
                    var count = new SpinRow (_("Count"), null, 1, 99, 1, cur.count);
                    count.spin_btn.value_changed.connect (() => cur.count = (int) count.spin_btn.value);
                    ng.add_row (count);
                    var unit = new SelectionRow (_("Unit"), units, units[(int) cur.unit]);
                    unit.selected.connect ((v) => {
                        for (int i = 0; i < units.length; i++) if (units[i] == v) cur.unit = (NestedUnit) i;
                    });
                    ng.add_row (unit);
                    if (cur.unit == NestedUnit.CHARACTER) {
                        var ch = new EntryRow (_("Character"));
                        ch.text = cur.character;
                        ch.entry_changed.connect (() => cur.character = ch.text);
                        ng.add_row (ch);
                    }
                    var rm = new ActionRow (_("Remove This Nested Style"));
                    var rb = new Button.with_label (_("Remove"));
                    rb.valign = Align.CENTER;
                    rb.clicked.connect (() => {
                        nested.remove (cur);
                        refill ();
                    });
                    rm.add_suffix (rb);
                    ng.add_row (rm);
                }
                var add_n = new ActionRow (_("Add a Nested Style"));
                var anb = new Button.with_label (_("Add"));
                anb.valign = Align.CENTER;
                anb.clicked.connect (() => {
                    nested.add (new NestedStyle (cnames[0]));
                    refill ();
                });
                add_n.add_suffix (anb);
                ng.add_row (add_n);
                foreach (var g in greps) {
                    var cur = g;
                    var cs = new SelectionRow (_("Character Style"), cnames, cur.cstyle != "" ? cur.cstyle : cnames[0]);
                    if (cur.cstyle == "") cur.cstyle = cnames[0];
                    cs.selected.connect ((v) => cur.cstyle = v);
                    gg.add_row (cs);
                    var pat = new EntryRow (_("Expression"));
                    pat.text = cur.pattern;
                    pat.entry_changed.connect (() => cur.pattern = pat.text);
                    gg.add_row (pat);
                    var rm = new ActionRow (_("Remove This GREP Style"));
                    var rb = new Button.with_label (_("Remove"));
                    rb.valign = Align.CENTER;
                    rb.clicked.connect (() => {
                        greps.remove (cur);
                        refill ();
                    });
                    rm.add_suffix (rb);
                    gg.add_row (rm);
                }
                var add_g = new ActionRow (_("Add a GREP Style"), _("For example \\d+ for numbers or \\b[A-Z]{2,}\\b for acronyms"));
                var agb = new Button.with_label (_("Add"));
                agb.valign = Align.CENTER;
                agb.clicked.connect (() => {
                    greps.add (new GrepStyle (cnames[0], ""));
                    refill ();
                });
                add_g.add_suffix (agb);
                gg.add_row (add_g);
                return false;
            };
            refill ();
            Dialogs.footer (dlg, _("Save"), () => {
                foreach (var g in greps) {
                    if (g.pattern != "" && StyleRules.compile (g.pattern) == null) {
                        w.show_error (_("Check the Expression"), _("“%s” is not a valid regular expression.").printf (g.pattern));
                        return;
                    }
                }
                w.edit (_("Nested and GREP Styles"), () => {
                    ps.nested.clear ();
                    ps.nested.add_all (nested);
                    ps.grep.clear ();
                    foreach (var g in greps) if (g.pattern != "") ps.grep.add (g);
                });
                w.canvas.relayout ();
            });
            dlg.open_dialog ();
        }

        public static void conditions (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Conditional Text"), 520, 640);
            var box = Dialogs.body (dlg);
            var cg = new PreferencesGroup (_("Conditions"), _("Text marked with a condition is shown or hidden everywhere, in print and export"));
            foreach (var c in pub.conditions) {
                var cond = c;
                var row = new SwitchRow (cond.name, null, cond.visible);
                row.switch_btn.notify["active"].connect (() => {
                    bool v = row.switch_btn.active;
                    if (v == cond.visible) return;
                    w.edit (_("Show Condition"), () => cond.visible = v);
                    w.canvas.relayout ();
                });
                var apply = new Button.with_label (_("Apply"));
                apply.valign = Align.CENTER;
                apply.tooltip_text = _("Mark the selected text with this condition");
                apply.clicked.connect (() => {
                    if (w.canvas.edit == null || !w.canvas.edit.has_selection ()) {
                        w.toast (_("Select some text first"));
                        return;
                    }
                    w.format_runs (_("Apply Condition"), (r) => r.condition = cond.name);
                });
                row.add_suffix (apply);
                cg.add_row (row);
            }
            var nr = new EntryRow (_("New Condition"));
            nr.entry_activated.connect (() => {
                string n = nr.text.strip ().replace (",", " ");
                if (n == "" || Conditions.find (pub, n) != null) return;
                w.edit (_("New Condition"), () => pub.conditions.add (new TextCondition (n)));
                dlg.close ();
                conditions (w);
            });
            cg.add_row (nr);
            var clear = new ActionRow (_("Remove Condition from Selection"));
            var cb = new Button.with_label (_("Remove"));
            cb.valign = Align.CENTER;
            cb.clicked.connect (() => w.format_runs (_("Remove Condition"), (r) => r.condition = ""));
            clear.add_suffix (cb);
            cg.add_row (clear);
            box.append (cg);
            var sg = new PreferencesGroup (_("Condition Sets"), _("Saved combinations of visible conditions, one per version of the document"));
            foreach (var s in pub.condition_sets) {
                var set = s;
                var row = new ActionRow (set.name, set.name == pub.active_condition_set ? _("Active") : null);
                var use = new Button.with_label (_("Use"));
                use.valign = Align.CENTER;
                use.clicked.connect (() => {
                    w.edit (_("Condition Set"), () => Conditions.apply_set (pub, set));
                    w.canvas.relayout ();
                    dlg.close ();
                    conditions (w);
                });
                row.add_suffix (use);
                sg.add_row (row);
            }
            var ns = new EntryRow (_("Save Current Visibility as Set"));
            ns.entry_activated.connect (() => {
                string n = ns.text.strip ();
                if (n == "") return;
                w.edit (_("New Condition Set"), () => {
                    foreach (var o in pub.condition_sets) if (o.name == n) {
                        pub.condition_sets.remove (o);
                        break;
                    }
                    pub.condition_sets.add (Conditions.capture (pub, n));
                    pub.active_condition_set = n;
                });
                dlg.close ();
                conditions (w);
            });
            sg.add_row (ns);
            box.append (sg);
            dlg.open_dialog ();
        }

        public static void index_entry (PublishWindow w) {
            var e = w.canvas.edit;
            if (e == null) {
                w.toast (_("Click in the text where the topic is discussed"));
                return;
            }
            string guess = "";
            if (e.has_selection ()) {
                TextPos a, b;
                e.ordered (out a, out b);
                guess = e.story.plain_range (a, b).replace (OBJ_STR, "").strip ();
            }
            var dlg = Dialogs.make (w, _("New Index Entry"), 480, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Topic"), _("Up to three levels, for example Printing, then Paper"));
            var t1 = new EntryRow (_("Topic"));
            t1.text = guess;
            g.add_row (t1);
            var t2 = new EntryRow (_("Subtopic"));
            g.add_row (t2);
            var t3 = new EntryRow (_("Third Level"));
            g.add_row (t3);
            var sort = new EntryRow (_("Sort As"));
            sort.tooltip_text = _("Optional: how the topic is alphabetised, for example Saint for St.");
            g.add_row (sort);
            box.append (g);
            var rg = new PreferencesGroup (_("Reference"));
            string[] kinds = { _("Current Page"), _("See"), _("See Also") };
            var kind = new SelectionRow (_("Type"), kinds, kinds[0]);
            rg.add_row (kind);
            var target = new EntryRow (_("Refer To Topic"));
            rg.add_row (target);
            box.append (rg);
            Dialogs.footer (dlg, _("Add"), () => {
                string[] topics = {};
                foreach (var en in new EntryRow[] { t1, t2, t3 }) if (en.text.strip () != "") topics += en.text.strip ();
                if (topics.length == 0) {
                    w.show_error (_("Name the Topic"), _("An index entry needs at least a topic."));
                    return;
                }
                var m = new IndexMarker ();
                m.topics = topics;
                for (int i = 0; i < kinds.length; i++) if (kinds[i] == kind.current_value) m.kind = i;
                m.target = target.text.strip ();
                m.sort_as = sort.text.strip ();
                if (m.kind != IndexMarker.PAGE && m.target == "") {
                    w.show_error (_("Choose the Topic to Refer To"), _("See and See Also entries point to another topic."));
                    return;
                }
                if (e.has_selection ()) {
                    TextPos a, b;
                    e.ordered (out a, out b);
                    e.collapse (a);
                }
                w.canvas.insert_field (m.to_field ());
                w.toast (_("Index entry added; choose Generate Index to update the index"));
            });
            dlg.open_dialog ();
        }

        public static void generate_index (PublishWindow w) {
            var pub = w.doc.pub;
            var cur = pub.index != null ? pub.index.clone () : new IndexSettings ();
            if (pub.index == null) cur.title = _("Index");
            var dlg = Dialogs.make (w, _("Generate Index"), 480, 420);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Index"), cur.story != 0 ? _("The existing index is replaced") : _("A new page with a two-column frame is added at the end"));
            var title = new EntryRow (_("Title"));
            title.text = cur.title;
            g.add_row (title);
            string[] codes = IndexBuilder.languages ();
            string[] names = { _("System Language"), _("English"), _("Italian"), _("German"), _("French"), _("Spanish"), _("Portuguese"), _("Dutch"), _("Swedish"), _("Danish"), _("Norwegian"), _("Finnish"), _("Polish"), _("Czech") };
            int li = 0;
            for (int i = 0; i < codes.length; i++) if (codes[i] == cur.language) li = i;
            var lang = new SelectionRow (_("Sort For"), names, names[li]);
            g.add_row (lang);
            var heads = new SwitchRow (_("Section Headings"), _("A, B, C before each group of topics"), cur.headings);
            g.add_row (heads);
            box.append (g);
            Dialogs.footer (dlg, _("Generate"), () => {
                cur.title = title.text.strip ();
                for (int i = 0; i < names.length; i++) if (names[i] == lang.current_value) cur.language = codes[i];
                cur.headings = heads.switch_btn.active;
                int n = 0;
                w.edit (_("Generate Index"), () => n = IndexBuilder.generate (pub, cur));
                w.canvas.relayout ();
                w.pages_panel.load ();
                w.toast (ngettext ("Index generated with %d topic", "Index generated with %d topics", n).printf (n));
            });
            dlg.open_dialog ();
        }

        public static void text_anchor (PublishWindow w) {
            var e = w.canvas.edit;
            if (e == null) {
                w.toast (_("Click in the paragraph that should become a destination"));
                return;
            }
            var para = e.story.paras[e.caret.para.clamp (0, e.story.paras.size - 1)];
            var dlg = Dialogs.make (w, _("Text Anchor"), 440, 300);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Name"), _("Cross-references and links can point to this paragraph by name"));
            var name = new EntryRow (_("Anchor Name"));
            name.text = para.anchor;
            g.add_row (name);
            box.append (g);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ().replace (":", "-");
                w.edit (_("Text Anchor"), () => para.anchor = n);
                w.canvas.relayout ();
            });
            dlg.open_dialog ();
        }

        public static void edit_note (PublishWindow w, Run run, bool fresh) {
            var dlg = Dialogs.make (w, fresh ? _("New Footnote") : _("Edit Footnote"), 480, 420);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Note Text"), _("Shown at the foot of the column where the reference falls, numbered automatically"));
            box.append (g);
            var tv = new TextView ();
            tv.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            tv.buffer.text = run.note != null ? run.note.plain_text () : "";
            tv.top_margin = tv.bottom_margin = tv.left_margin = tv.right_margin = 8;
            var frame = new ScrolledWindow ();
            frame.min_content_height = 140;
            frame.child = tv;
            frame.add_css_class ("card");
            box.append (frame);
            Dialogs.footer (dlg, _("Save"), () => {
                string text = tv.buffer.text.strip ();
                w.edit (_("Footnote"), () => {
                    var fresh_note = new Story.from_text (0, text, Footnotes.is_endnote (run) ? FootnoteOptions.END_STYLE : w.doc.pub.footnotes.para_style);
                    if (run.note != null && run.note.paras.size > 0 && run.note.plain_text () != "") {
                        string style = run.note.paras[0].style;
                        foreach (var p in fresh_note.paras) p.style = style;
                    }
                    run.note = fresh_note;
                    if (Footnotes.is_endnote (run)) Footnotes.update_endnotes (w.doc.pub, _("Notes"));
                });
                w.canvas.relayout ();
            });
            dlg.open_dialog ();
        }

        public static void footnote_options (PublishWindow w) {
            var pub = w.doc.pub;
            var o = pub.footnotes;
            Footnotes.ensure_style (pub);
            var dlg = Dialogs.make (w, _("Footnote Options"), 500, 680);
            var box = Dialogs.body (dlg);
            var ng = new PreferencesGroup (_("Numbering"));
            string[] nums = FootnoteOptions.numbering_labels ();
            var numbering = new SelectionRow (_("Style"), nums, nums[o.numbering.clamp (0, nums.length - 1)]);
            ng.add_row (numbering);
            var start = spin (ng, _("Start At"), 1, 9999, 1, o.start);
            string[] restarts = FootnoteOptions.restart_labels ();
            var restart = new SelectionRow (_("Restart Numbering"), restarts, restarts[o.restart.clamp (0, restarts.length - 1)]);
            ng.add_row (restart);
            var prefix = new EntryRow (_("Prefix"));
            prefix.text = o.prefix;
            ng.add_row (prefix);
            var suffix = new EntryRow (_("Suffix"));
            suffix.text = o.suffix;
            ng.add_row (suffix);
            box.append (ng);
            var fg = new PreferencesGroup (_("Formatting"));
            string[] pstyles = {};
            foreach (var ps in pub.styles.paragraph) pstyles += ps.name;
            var pstyle = new SelectionRow (_("Note Paragraph Style"), pstyles, o.para_style);
            fg.add_row (pstyle);
            string[] cstyles = { _("Superscript") };
            foreach (var cs in pub.styles.character) cstyles += cs.name;
            var rstyle = new SelectionRow (_("Reference Character Style"), cstyles, o.ref_style == "" ? cstyles[0] : o.ref_style);
            fg.add_row (rstyle);
            box.append (fg);
            var lg = new PreferencesGroup (_("Layout"));
            var before = spin (lg, _("Space Above the Notes (pt)"), 0, 72, 0.5, o.space_before, 1);
            var between = spin (lg, _("Space Between Notes (pt)"), 0, 72, 0.5, o.space_between, 1);
            var split = new SwitchRow (_("Allow Split Footnotes"), _("A long note may continue in the next column"), o.split);
            lg.add_row (split);
            var rule = new SwitchRow (_("Rule Above"), null, o.rule);
            lg.add_row (rule);
            var weight = spin (lg, _("Rule Weight (pt)"), 0.1, 12, 0.1, o.rule_weight, 1);
            var length = spin (lg, _("Rule Length (pt)"), 6, 2000, 1, o.rule_length);
            box.append (lg);
            Dialogs.footer (dlg, _("Apply"), () => {
                var n = o.clone ();
                for (int i = 0; i < nums.length; i++) if (nums[i] == numbering.current_value) n.numbering = i;
                for (int i = 0; i < restarts.length; i++) if (restarts[i] == restart.current_value) n.restart = i;
                n.start = (int) start.spin_btn.value;
                n.prefix = prefix.text;
                n.suffix = suffix.text;
                n.para_style = pstyle.current_value;
                n.ref_style = rstyle.current_value == cstyles[0] ? "" : rstyle.current_value;
                n.space_before = before.spin_btn.value;
                n.space_between = between.spin_btn.value;
                n.split = split.switch_btn.active;
                n.rule = rule.switch_btn.active;
                n.rule_weight = weight.spin_btn.value;
                n.rule_length = length.spin_btn.value;
                w.edit (_("Footnote Options"), () => pub.footnotes = n);
                w.canvas.relayout ();
            });
            dlg.open_dialog ();
        }

        public static void table_continue (PublishWindow w) {
            var pub = w.doc.pub;
            var t = selected_table (w);
            if (t == null) {
                w.toast (_("Select a table first"));
                return;
            }
            var chain = TableFlow.chain (pub, t);
            var tail = chain[chain.size - 1];
            var head = chain[0];
            var ref_ = pub.find_item (tail.id);
            if (ref_ == null || ref_.page == null) {
                w.toast (_("Only tables on pages can continue"));
                return;
            }
            int pi = pub.pages.index_of (ref_.page);
            w.canvas.end_edit ();
            TableItem? cont = null;
            w.edit (_("Continue Table"), () => {
                if (pi + 1 >= pub.pages.size) pub.add_page (-1, ref_.page.master);
                var mr = pub.margin_rect (pi + 1);
                double total = 0;
                foreach (var v in head.row_h) total += v;
                var hr = pub.find_item (head.id);
                if (hr != null && hr.page != null && chain.size == 1) {
                    var hm = pub.margin_rect (pub.pages.index_of (hr.page));
                    double room = hm.y + hm.h - head.y;
                    if (room > 20 && total > room) head.h = room;
                }
                cont = new TableItem (0, 0);
                cont.id = pub.next_id ();
                cont.layer = tail.layer;
                cont.x = mr.x;
                cont.y = mr.y;
                cont.w = head.w;
                cont.h = mr.h;
                cont.border_width = 0;
                cont.continue_from = tail.id;
                tail.continue_to = cont.id;
                pub.pages[pi + 1].items.add (cont);
            });
            if (cont != null) {
                w.go_to_page (pi + 1);
                w.canvas.select_only (cont);
                w.toast (_("The table continues on page %s").printf (pub.page_label (pi + 1)));
            }
        }

        public static void table_options (PublishWindow w) {
            var pub = w.doc.pub;
            var t = selected_table (w);
            if (t == null) {
                w.toast (_("Select a table first"));
                return;
            }
            var head = TableFlow.head (pub, t);
            var dlg = Dialogs.make (w, _("Table Options"), 440, 400);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Header"), _("Header rows repeat at the top of every frame the table continues into"));
            var hr = new SpinRow (_("Header Rows"), null, 0, head.rows, 1, head.header_rows);
            g.add_row (hr);
            var rep = new SwitchRow (_("Repeat Header"), null, head.repeat_header);
            g.add_row (rep);
            box.append (g);
            var fg = new PreferencesGroup (_("Continuation"));
            var chain = TableFlow.chain (pub, t);
            bool overset;
            TableFlow.assign (pub, head, out overset);
            fg.add_row (new ActionRow (_("Frames"), ngettext ("%d frame", "%d frames", chain.size).printf (chain.size) + (overset ? ", " + _("some rows do not fit") : "")));
            var more = new ActionRow (_("Continue in Another Frame"), _("Adds a frame on the next page for the rows that do not fit"));
            var mb = new Button.with_label (_("Continue"));
            mb.valign = Align.CENTER;
            mb.clicked.connect (() => {
                dlg.close ();
                table_continue (w);
            });
            more.add_suffix (mb);
            fg.add_row (more);
            if (t.continue_from != 0) {
                var cut = new ActionRow (_("Stop Continuing Here"), _("Removes this frame from the table"));
                var cb = new Button.with_label (_("Remove"));
                cb.valign = Align.CENTER;
                cb.clicked.connect (() => {
                    dlg.close ();
                    w.edit (_("Remove Table Frame"), () => {
                        var pr = pub.find_item (t.continue_from);
                        var prev = pr != null ? pr.item as TableItem : null;
                        if (prev != null) prev.continue_to = t.continue_to;
                        if (t.continue_to != 0) {
                            var nr = pub.find_item (t.continue_to);
                            var nx = nr != null ? nr.item as TableItem : null;
                            if (nx != null) nx.continue_from = t.continue_from;
                        }
                        var me = pub.find_item (t.id);
                        if (me != null) me.list.remove (t);
                    });
                });
                cut.add_suffix (cb);
                fg.add_row (cut);
            }
            box.append (fg);
            Dialogs.footer (dlg, _("Apply"), () => {
                int h = (int) hr.spin_btn.value;
                bool r = rep.switch_btn.active;
                w.edit (_("Table Options"), () => {
                    head.header_rows = h;
                    head.repeat_header = r;
                });
            });
            dlg.open_dialog ();
        }

        public static void anchored (PublishWindow w) {
            var e = w.canvas.edit;
            Run? run = null;
            if (e != null) {
                run = e.story.anchor_near (e.caret);
                if (run == null && e.has_selection ()) run = e.story.anchor_near (e.anchor);
            }
            if (run == null) {
                w.toast (_("Place the text cursor next to an anchored object; paste a copied object into text to anchor it"));
                return;
            }
            var spec = run.anchor_spec;
            var dlg = Dialogs.make (w, _("Anchored Object Options"), 460, 460);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Position"));
            string[] modes = { _("Inline, Moves with the Text"), _("Custom, Relative to the Anchor") };
            var mode = new SelectionRow (_("Position"), modes, modes[spec.mode == 1 ? 1 : 0]);
            g.add_row (mode);
            string[] refs = { _("Anchor Marker"), _("Text Frame Edge") };
            var xref = new SelectionRow (_("Horizontal Reference"), refs, refs[spec.x_ref == 1 ? 1 : 0]);
            g.add_row (xref);
            var dx = new SpinRow (_("Horizontal Offset (pt)"), null, -2000, 2000, 1, spec.x_offset);
            g.add_row (dx);
            var dy = new SpinRow (_("Vertical Offset (pt)"), _("Inline: shift from the baseline; custom: from the baseline to the top of the object"), -2000, 2000, 1, spec.y_offset);
            g.add_row (dy);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                int m = mode.current_value == modes[1] ? 1 : 0;
                int xr = xref.current_value == refs[1] ? 1 : 0;
                double ox = dx.spin_btn.value, oy = dy.spin_btn.value;
                w.edit (_("Anchored Object"), () => {
                    spec.mode = m;
                    spec.x_ref = xr;
                    spec.x_offset = ox;
                    spec.y_offset = oy;
                });
                w.content_edited ();
            });
            dlg.open_dialog ();
        }

        public static void variables (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Text Variables"), 520, 620);
            var box = Dialogs.body (dlg);
            var cg = new PreferencesGroup (_("Document"));
            var chap = new SpinRow (_("Chapter Number"), _("Used by Chapter Number variables and by books"), 1, 9999, 1, pub.chapter_number);
            chap.spin_btn.value_changed.connect (() => w.edit (_("Chapter Number"), () => pub.chapter_number = (int) chap.spin_btn.value, "chapter"));
            cg.add_row (chap);
            box.append (cg);
            var lg = new PreferencesGroup (_("Variables"), _("Insert a variable where the text should change on its own"));
            header_add (lg, w, dlg);
            foreach (var v in pub.text_vars) {
                var tv = v;
                var row = new ActionRow (tv.name, TextVariable.kind_label (tv.kind) + (tv.kind == "running" ? ": " + tv.style : (tv.kind == "custom" ? ": " + tv.text : "")));
                var ins = new Button.with_label (_("Insert"));
                ins.valign = Align.CENTER;
                ins.clicked.connect (() => {
                    dlg.close ();
                    w.insert_field_or_frame (Fields.variable (tv.name));
                });
                var ed = new Button.from_icon_name ("document-edit-symbolic");
                ed.add_css_class ("flat");
                ed.valign = Align.CENTER;
                ed.tooltip_text = _("Edit");
                ed.clicked.connect (() => {
                    dlg.close ();
                    edit_variable (w, tv);
                });
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Delete");
                del.clicked.connect (() => {
                    w.edit (_("Delete Variable"), () => pub.text_vars.remove (tv));
                    dlg.close ();
                    variables (w);
                });
                row.add_suffix (ins);
                row.add_suffix (ed);
                row.add_suffix (del);
                lg.add_row (row);
            }
            box.append (lg);
            Dialogs.footer (dlg, _("Done"), () => {});
            dlg.open_dialog ();
        }

        private static void header_add (PreferencesGroup g, PublishWindow w, AppDialog dlg) {
            var b = new Button.with_label (_("New…"));
            b.valign = Align.CENTER;
            b.clicked.connect (() => {
                dlg.close ();
                edit_variable (w, null);
            });
            g.add_header_suffix (b);
        }

        public static void edit_variable (PublishWindow w, TextVariable? existing) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, existing == null ? _("New Text Variable") : _("Edit Text Variable"), 480, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Variable"));
            var name = new EntryRow (_("Name"));
            name.text = existing != null ? existing.name : _("Running Header");
            g.add_row (name);
            string[] kinds = TextVariable.kinds ();
            string[] labels = {};
            foreach (string k in kinds) labels += TextVariable.kind_label (k);
            var kind = new SelectionRow (_("Type"), labels, TextVariable.kind_label (existing != null ? existing.kind : "running"));
            g.add_row (kind);
            var text = new EntryRow (_("Text"));
            text.text = existing != null ? existing.text : "";
            g.add_row (text);
            string[] styles = {};
            foreach (var st in pub.styles.paragraph) styles += st.name;
            string cur_style = existing != null && existing.style != "" ? existing.style : (pub.styles.find_paragraph ("Heading 1") != null ? "Heading 1" : styles[0]);
            var style = new SelectionRow (_("Paragraph Style"), styles, cur_style);
            g.add_row (style);
            string[] uses = { _("First on Page"), _("Last on Page") };
            var use = new SelectionRow (_("Use"), uses, uses[existing != null && existing.use_last ? 1 : 0]);
            g.add_row (use);
            var before = new EntryRow (_("Text Before"));
            before.text = existing != null ? existing.before : "";
            g.add_row (before);
            var after = new EntryRow (_("Text After"));
            after.text = existing != null ? existing.after : "";
            g.add_row (after);
            box.append (g);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                string k = kinds[0];
                for (int i = 0; i < kinds.length; i++) if (labels[i] == kind.current_value) k = kinds[i];
                var v = new TextVariable (n, k);
                v.text = text.text;
                v.style = style.current_value;
                v.use_last = use.current_value == uses[1];
                v.before = before.text;
                v.after = after.text;
                w.edit (_("Text Variable"), () => {
                    if (existing != null) pub.text_vars.remove (existing);
                    var clash = pub.text_var (n);
                    if (clash != null) pub.text_vars.remove (clash);
                    pub.text_vars.add (v);
                });
                variables (w);
            });
            dlg.open_dialog ();
        }
    }

    public class ObjectStyleDialog {
        public static void open (PublishWindow w, ObjectStyle os) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Object Style"), 480, 640);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("General"));
            var name = new EntryRow (_("Name"));
            name.text = os.name;
            g.add_row (name);
            string[] parents = { _("None") };
            foreach (var o in pub.object_styles) if (o != os) parents += o.name;
            var based = new SelectionRow (_("Based On"), parents, os.based_on != "" ? os.based_on : parents[0]);
            g.add_row (based);
            box.append (g);
            var cg = new PreferencesGroup (_("Applies"), _("Only the parts switched on are changed on the objects"));
            var f1 = new SwitchRow (_("Fill"), null, os.use_fill);
            cg.add_row (f1);
            var f2 = new SwitchRow (_("Stroke"), null, os.use_stroke);
            cg.add_row (f2);
            var f3 = new SwitchRow (_("Opacity, Shadow and Effects"), null, os.use_effects);
            cg.add_row (f3);
            var f4 = new SwitchRow (_("Corners"), null, os.use_corner);
            cg.add_row (f4);
            var f5 = new SwitchRow (_("Text Wrap"), null, os.use_wrap);
            cg.add_row (f5);
            var f6 = new SwitchRow (_("Text Frame Options"), _("Insets, columns and vertical alignment"), os.use_frame);
            cg.add_row (f6);
            var f7 = new SwitchRow (_("Paragraph Style"), null, os.use_para);
            cg.add_row (f7);
            string[] styles = {};
            foreach (var st in pub.styles.paragraph) styles += st.name;
            var ps = new SelectionRow (_("Paragraph Style"), styles, os.para_style != "" ? os.para_style : StyleSheet.BASIC);
            cg.add_row (ps);
            box.append (cg);
            var rg = new PreferencesGroup (_("Values"));
            var redefine = new ActionRow (_("Redefine from Selection"), _("Take the fill, stroke, effects and frame options of the selected object"));
            var rb = new Button.with_label (_("Redefine"));
            rb.valign = Align.CENTER;
            rb.clicked.connect (() => {
                var items = w.sel ();
                if (items.size == 0) {
                    w.toast (_("Select an object first"));
                    return;
                }
                var fresh = ObjectStyle.from_item (os.name, items[0], pub);
                w.edit (_("Redefine Object Style"), () => os.proto = fresh.proto);
                w.toast (_("Redefined \"%s\"").printf (os.name));
            });
            redefine.add_suffix (rb);
            rg.add_row (redefine);
            box.append (rg);
            Dialogs.footer (dlg, _("Save"), () => {
                string nm = name.text.strip ();
                if (nm == "") return;
                string parent = based.current_value == parents[0] ? "" : based.current_value;
                string old = os.name;
                w.edit (_("Object Style"), () => {
                    if (nm != old && pub.object_style (nm) == null) {
                        os.name = nm;
                        foreach (var o in pub.object_styles) if (o.based_on == old) o.based_on = nm;
                        pub.walk ((r) => {
                            if (r.item.object_style == old) r.item.object_style = nm;
                            return true;
                        });
                    }
                    os.based_on = parent;
                    os.use_fill = f1.switch_btn.active;
                    os.use_stroke = f2.switch_btn.active;
                    os.use_effects = f3.switch_btn.active;
                    os.use_corner = f4.switch_btn.active;
                    os.use_wrap = f5.switch_btn.active;
                    os.use_frame = f6.switch_btn.active;
                    os.use_para = f7.switch_btn.active;
                    os.para_style = ps.current_value;
                    pub.walk ((r) => {
                        if (r.item.object_style == os.name) os.apply_to (pub, r.item);
                        return true;
                    });
                });
                w.styles_panel.rebuild ();
                w.canvas.queue_draw ();
            });
            dlg.open_dialog ();
        }
    }
}

namespace Singularity.Apps.Publish {

    public class TableStyleDialog {
        private static string[] with_none (Gee.List<string> names) {
            string[] l = { _("None") };
            foreach (string n in names) l += n;
            return l;
        }

        private static string pick (SelectionRow row) {
            return row.current_value == _("None") ? "" : row.current_value;
        }

        public static void table (PublishWindow w, TableStyle ts) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Table Style"), 500, 680);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("General"));
            var name = new EntryRow (_("Name"));
            name.text = ts.name;
            g.add_row (name);
            var tnames = new Gee.ArrayList<string> ();
            foreach (var o in pub.table_styles) if (o != ts) tnames.add (o.name);
            var based = new SelectionRow (_("Based On"), with_none (tnames), ts.based_on != "" ? ts.based_on : _("None"));
            g.add_row (based);
            box.append (g);
            var cnames = new Gee.ArrayList<string> ();
            foreach (var c in pub.cell_styles) cnames.add (c.name);
            var rg = new PreferencesGroup (_("Cell Styles"), _("Used by cells that have no cell style of their own"));
            var hc = new SelectionRow (_("Header Rows"), with_none (cnames), ts.header_cell != "" ? ts.header_cell : _("None"));
            rg.add_row (hc);
            var bc = new SelectionRow (_("Body Rows"), with_none (cnames), ts.body_cell != "" ? ts.body_cell : _("None"));
            rg.add_row (bc);
            var fc = new SelectionRow (_("First Column"), with_none (cnames), ts.first_col_cell != "" ? ts.first_col_cell : _("None"));
            rg.add_row (fc);
            box.append (rg);
            var lg = new PreferencesGroup (_("Borders and Fills"));
            string border = ts.border_color, header = ts.header_fill, alt = ts.alt_fill;
            var bw = new SpinRow (_("Border Weight (pt)"), null, 0, 20, 0.25, ts.border_width >= 0 ? ts.border_width : 0.5);
            bw.spin_btn.digits = 2;
            lg.add_row (bw);
            var hf = new EntryRow (_("Header Fill (colour or swatch)"));
            hf.text = header;
            lg.add_row (hf);
            var af = new EntryRow (_("Alternating Fill (colour or swatch)"));
            af.text = alt;
            lg.add_row (af);
            var be = new EntryRow (_("Border Colour (colour or swatch)"));
            be.text = border;
            lg.add_row (be);
            var inset = new SpinRow (_("Cell Inset (pt)"), null, 0, 72, 0.5, ts.cell_inset >= 0 ? ts.cell_inset : 4);
            inset.spin_btn.digits = 1;
            lg.add_row (inset);
            var rep = new SwitchRow (_("Repeat Header Rows"), _("In every frame the table continues into"), ts.repeat_header != 0);
            lg.add_row (rep);
            box.append (lg);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                string old = ts.name;
                w.edit (_("Table Style"), () => {
                    ts.name = n;
                    string b = pick (based);
                    ts.based_on = b == n ? "" : b;
                    ts.header_cell = pick (hc);
                    ts.body_cell = pick (bc);
                    ts.first_col_cell = pick (fc);
                    ts.border_width = bw.spin_btn.value;
                    ts.header_fill = hf.text.strip ();
                    ts.alt_fill = af.text.strip ();
                    ts.border_color = be.text.strip ();
                    ts.cell_inset = inset.spin_btn.value;
                    ts.repeat_header = rep.switch_btn.active ? 1 : 0;
                    if (old != n) {
                        foreach (var o in pub.table_styles) if (o.based_on == old) o.based_on = n;
                        pub.walk ((r) => {
                            var t = r.item as TableItem;
                            if (t != null && t.table_style == old) t.table_style = n;
                            return true;
                        });
                    }
                    TableStyles.update_all (pub);
                });
                w.canvas.relayout ();
                w.inspector.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void cell (PublishWindow w, CellStyle cs) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Cell Style"), 480, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("General"));
            var name = new EntryRow (_("Name"));
            name.text = cs.name;
            g.add_row (name);
            var cnames = new Gee.ArrayList<string> ();
            foreach (var o in pub.cell_styles) if (o != cs) cnames.add (o.name);
            var based = new SelectionRow (_("Based On"), with_none (cnames), cs.based_on != "" ? cs.based_on : _("None"));
            g.add_row (based);
            box.append (g);
            var fg = new PreferencesGroup (_("Cell"));
            var fill = new EntryRow (_("Fill (colour or swatch)"));
            fill.text = cs.fill;
            fg.add_row (fill);
            string[] va = { _("Not Set"), _("Top"), _("Center"), _("Bottom") };
            var valign = new SelectionRow (_("Vertical Alignment"), va, va[(cs.valign + 1).clamp (0, 3)]);
            fg.add_row (valign);
            string[] dg = { _("Not Set"), _("None"), _("Top Left to Bottom Right"), _("Bottom Left to Top Right") };
            var diag = new SelectionRow (_("Diagonal Line"), dg, dg[(cs.diagonal + 1).clamp (0, 3)]);
            fg.add_row (diag);
            var pnames = new Gee.ArrayList<string> ();
            foreach (var ps in pub.styles.paragraph) pnames.add (ps.name);
            var para = new SelectionRow (_("Paragraph Style"), with_none (pnames), cs.para_style != "" ? cs.para_style : _("None"));
            fg.add_row (para);
            box.append (fg);
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                string old = cs.name;
                w.edit (_("Cell Style"), () => {
                    cs.name = n;
                    string b = pick (based);
                    cs.based_on = b == n ? "" : b;
                    cs.fill = fill.text.strip ();
                    for (int i = 0; i < va.length; i++) if (va[i] == valign.current_value) cs.valign = i - 1;
                    for (int i = 0; i < dg.length; i++) if (dg[i] == diag.current_value) cs.diagonal = i - 1;
                    cs.para_style = pick (para);
                    if (old != n) {
                        foreach (var o in pub.cell_styles) if (o.based_on == old) o.based_on = n;
                        foreach (var t in pub.table_styles) {
                            if (t.header_cell == old) t.header_cell = n;
                            if (t.body_cell == old) t.body_cell = n;
                            if (t.first_col_cell == old) t.first_col_cell = n;
                        }
                        pub.walk ((r) => {
                            var t = r.item as TableItem;
                            if (t != null) foreach (var rw in t.cells) foreach (var c in rw) if (c.cell_style == old) c.cell_style = n;
                            return true;
                        });
                    }
                    TableStyles.update_all (pub);
                });
                w.canvas.relayout ();
            });
            dlg.open_dialog ();
        }
    }
}
