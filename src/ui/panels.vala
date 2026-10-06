using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public abstract class Panel : Box {
        protected PublishWindow win;
        protected Box content;

        protected Panel (PublishWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.add_css_class ("publish-panel-scroll");
            content = new Box (Orientation.VERTICAL, 18);
            content.add_css_class ("publish-panel");
            scroll.child = content;
            append (scroll);
        }

        protected Publication pub {
            get { return win.doc.pub; }
        }

        protected void clear () {
            Widget? c;
            while ((c = content.get_first_child ()) != null) content.remove (c);
        }

        protected PreferencesGroup group (string title, string? desc = null) {
            var g = new PreferencesGroup (title, desc);
            content.append (g);
            return g;
        }

        protected Button header_button (PreferencesGroup g, string label, owned Document.EditFunc f) {
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            b.clicked.connect (() => f ());
            g.add_header_suffix (b);
            return b;
        }

        protected Button icon (string name, string tip) {
            var b = new Button.from_icon_name (name);
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            b.tooltip_text = tip;
            return b;
        }

        public abstract void rebuild ();
    }

    public class StylesPanel : Panel {
        public StylesPanel (PublishWindow win) {
            base (win);
        }

        public void sync_current () {
            rebuild ();
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            var para = win.current_paragraph ();
            var pg = group (_("Paragraph Styles"), _("Click a style to apply it to the selected paragraphs"));
            header_button (pg, _("Import…"), () => win.run ("import-styles"));
            header_button (pg, _("New"), () => Dialogs.edit_paragraph_style (win, null));
            var pgroups = new Gee.ArrayList<string> ();
            foreach (var st in pub.styles.paragraph) if (st.group != "" && !pgroups.contains (st.group)) pgroups.add (st.group);
            foreach (var st in pub.styles.paragraph) if (st.group == "") add_paragraph_row (pg, st, para);
            var redefine = new ActionRow (_("Redefine from Selection"), _("Copy the local formatting of the current paragraph into its style"));
            var rb = new Button.with_label (_("Redefine"));
            rb.valign = Align.CENTER;
            rb.clicked.connect (() => redefine_style ());
            redefine.add_suffix (rb);
            pg.add_row (redefine);
            foreach (string gname in pgroups) {
                var gg = group (gname, _("Paragraph style group"));
                foreach (var st in pub.styles.paragraph) if (st.group == gname) add_paragraph_row (gg, st, para);
            }
            var cg = group (_("Character Styles"));
            header_button (cg, _("New"), () => Dialogs.edit_character_style (win, null));
            var cgroups = new Gee.ArrayList<string> ();
            foreach (var st in pub.styles.character) if (st.group != "" && !cgroups.contains (st.group)) cgroups.add (st.group);
            foreach (var st in pub.styles.character) {
                var s = st;
                if (s.group != "") continue;
                var row = new ActionRow (s.name, s.based_on != "" ? _("based on %s").printf (s.based_on) : null);
                var apply = icon ("object-select-symbolic", _("Apply"));
                apply.clicked.connect (() => win.format_runs (_("Character Style"), (r) => r.cstyle = s.name));
                row.add_suffix (apply);
                var ed = icon ("document-edit-symbolic", _("Edit Style"));
                ed.clicked.connect (() => Dialogs.edit_character_style (win, s));
                row.add_suffix (ed);
                var del = icon ("user-trash-symbolic", _("Delete Style"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Style"), () => {
                        pub.styles.character.remove (s);
                        foreach (var o in pub.styles.character) if (o.based_on == s.name) o.based_on = "";
                        foreach (var story in pub.stories.values) foreach (var p in story.paras) foreach (var r in p.runs) if (r.cstyle == s.name) r.cstyle = "";
                    });
                    rebuild ();
                });
                row.add_suffix (del);
                cg.add_row (row);
            }
            foreach (string gname in cgroups) {
                var gg = group (gname, _("Character style group"));
                foreach (var st in pub.styles.character) {
                    var s = st;
                    if (s.group != gname) continue;
                    var row = new ActionRow (s.name, s.based_on != "" ? _("based on %s").printf (s.based_on) : null);
                    var apply = icon ("object-select-symbolic", _("Apply"));
                    apply.clicked.connect (() => win.format_runs (_("Character Style"), (r) => r.cstyle = s.name));
                    row.add_suffix (apply);
                    var ed = icon ("document-edit-symbolic", _("Edit Style"));
                    ed.clicked.connect (() => Dialogs.edit_character_style (win, s));
                    row.add_suffix (ed);
                    gg.add_row (row);
                }
            }
            var clear_row = new ActionRow (_("No Character Style"));
            var cb = icon ("edit-clear-symbolic", _("Remove Character Style"));
            cb.clicked.connect (() => win.format_runs (_("Character Style"), (r) => r.cstyle = ""));
            clear_row.add_suffix (cb);
            cg.add_row (clear_row);
            object_styles_group ();
            table_styles_group ();
        }

        private void table_styles_group () {
            var tg = group (_("Table Styles"), _("Borders, fills and the cell styles of header and body rows"));
            header_button (tg, _("New"), () => {
                var t = win.sel ().size > 0 ? win.sel ()[0] as TableItem : null;
                string nm = _("Table Style %d").printf (pub.table_styles.size + 1);
                var ts = t != null ? TableStyles.from_table (nm, t) : new TableStyle (nm);
                win.edit (_("New Table Style"), () => {
                    pub.table_styles.add (ts);
                    if (t != null) t.table_style = nm;
                });
                TableStyleDialog.table (win, ts);
            });
            foreach (var st in pub.table_styles) {
                var ts = st;
                var row = new ActionRow (ts.name, ts.based_on != "" ? _("based on %s").printf (ts.based_on) : null);
                var apply = icon ("object-select-symbolic", _("Apply to Selected Table"));
                apply.clicked.connect (() => {
                    var t = win.sel ().size > 0 ? win.sel ()[0] as TableItem : null;
                    if (t == null) {
                        win.toast (_("Select a table first"));
                        return;
                    }
                    win.edit (_("Table Style"), () => TableStyles.apply_table (pub, t, ts.name));
                    rebuild ();
                });
                row.add_suffix (apply);
                var ed = icon ("document-edit-symbolic", _("Edit Style"));
                ed.clicked.connect (() => TableStyleDialog.table (win, ts));
                row.add_suffix (ed);
                var del = icon ("user-trash-symbolic", _("Delete Style"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Style"), () => {
                        pub.table_styles.remove (ts);
                        foreach (var o in pub.table_styles) if (o.based_on == ts.name) o.based_on = "";
                        pub.walk ((r) => {
                            var t = r.item as TableItem;
                            if (t != null && t.table_style == ts.name) t.table_style = "";
                            return true;
                        });
                    });
                    rebuild ();
                });
                row.add_suffix (del);
                tg.add_row (row);
            }
            var cg = group (_("Cell Styles"), _("Fill, alignment, diagonal line and paragraph style of cells"));
            header_button (cg, _("New"), () => {
                string nm = _("Cell Style %d").printf (pub.cell_styles.size + 1);
                var cs = new CellStyle (nm);
                win.edit (_("New Cell Style"), () => pub.cell_styles.add (cs));
                TableStyleDialog.cell (win, cs);
            });
            foreach (var st in pub.cell_styles) {
                var cs = st;
                var row = new ActionRow (cs.name, cs.based_on != "" ? _("based on %s").printf (cs.based_on) : null);
                var apply = icon ("object-select-symbolic", _("Apply to Selected Cells"));
                apply.clicked.connect (() => {
                    var t = win.sel ().size > 0 ? win.sel ()[0] as TableItem : null;
                    if (t == null || win.canvas.cell_r1 < 0) {
                        win.toast (_("Select table cells first"));
                        return;
                    }
                    int r1 = int.min (win.canvas.cell_r1, win.canvas.cell_r2), r2 = int.max (win.canvas.cell_r1, win.canvas.cell_r2);
                    int c1 = int.min (win.canvas.cell_c1, win.canvas.cell_c2), c2 = int.max (win.canvas.cell_c1, win.canvas.cell_c2);
                    win.edit (_("Cell Style"), () => {
                        for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) TableStyles.apply_cell (pub, t.cells[r][c], cs.name);
                    });
                });
                row.add_suffix (apply);
                var ed = icon ("document-edit-symbolic", _("Edit Style"));
                ed.clicked.connect (() => TableStyleDialog.cell (win, cs));
                row.add_suffix (ed);
                var del = icon ("user-trash-symbolic", _("Delete Style"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Style"), () => {
                        pub.cell_styles.remove (cs);
                        foreach (var o in pub.cell_styles) if (o.based_on == cs.name) o.based_on = "";
                        foreach (var t in pub.table_styles) {
                            if (t.header_cell == cs.name) t.header_cell = "";
                            if (t.body_cell == cs.name) t.body_cell = "";
                            if (t.first_col_cell == cs.name) t.first_col_cell = "";
                        }
                        pub.walk ((r) => {
                            var t = r.item as TableItem;
                            if (t != null) foreach (var rw in t.cells) foreach (var c in rw) if (c.cell_style == cs.name) c.cell_style = "";
                            return true;
                        });
                    });
                    rebuild ();
                });
                row.add_suffix (del);
                cg.add_row (row);
            }
        }

        private void object_styles_group () {
            var og = group (_("Object Styles"), _("Fill, stroke, effects, corners, wrap and frame options applied together"));
            header_button (og, _("New from Selection"), () => {
                var items = win.sel ();
                if (items.size == 0) {
                    win.toast (_("Select an object first"));
                    return;
                }
                string nm = _("Object Style %d").printf (pub.object_styles.size + 1);
                var os = ObjectStyle.from_item (nm, items[0], pub);
                win.edit (_("New Object Style"), () => {
                    pub.object_styles.add (os);
                    items[0].object_style = nm;
                });
                ObjectStyleDialog.open (win, os);
            });
            var current = win.sel ().size > 0 ? win.sel ()[0].object_style : "";
            foreach (var st in pub.object_styles) {
                var os = st;
                var row = new ActionRow (os.name, os.based_on != "" ? _("based on %s").printf (os.based_on) : null);
                if (os.name == current) row.add_css_class ("accent");
                var apply = icon ("object-select-symbolic", _("Apply to Selection"));
                apply.clicked.connect (() => {
                    var items = win.sel ();
                    if (items.size == 0) {
                        win.toast (_("Select an object first"));
                        return;
                    }
                    win.edit (_("Object Style"), () => {
                        foreach (var it in items) os.apply_to (pub, it);
                    });
                    rebuild ();
                });
                row.add_suffix (apply);
                var ed = icon ("document-edit-symbolic", _("Edit Style"));
                ed.clicked.connect (() => ObjectStyleDialog.open (win, os));
                row.add_suffix (ed);
                var del = icon ("user-trash-symbolic", _("Delete Style"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Style"), () => {
                        pub.object_styles.remove (os);
                        foreach (var o in pub.object_styles) if (o.based_on == os.name) o.based_on = "";
                        pub.walk ((r) => {
                            if (r.item.object_style == os.name) r.item.object_style = "";
                            return true;
                        });
                    });
                    rebuild ();
                });
                row.add_suffix (del);
                og.add_row (row);
            }
        }

        private void add_paragraph_row (PreferencesGroup pg, ParagraphStyle s, Paragraph? para) {
            var chain = new StringBuilder ();
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (s.name, pf, cf);
            chain.append ("%s %s".printf (cf.font ?? "", XmlOut.num (cf.size) + " pt"));
            if (s.based_on != "") chain.append (", " + _("based on %s").printf (s.based_on));
            var row = new ActionRow (s.name, chain.str);
            if (para != null && para.style == s.name) row.add_css_class ("accent");
            var apply = icon ("object-select-symbolic", _("Apply"));
            apply.clicked.connect (() => win.format_paras (_("Paragraph Style"), (p) => p.style = s.name));
            row.add_suffix (apply);
            var ed = icon ("document-edit-symbolic", _("Edit Style"));
            ed.clicked.connect (() => Dialogs.edit_paragraph_style (win, s));
            row.add_suffix (ed);
            row.activated.connect (() => win.format_paras (_("Paragraph Style"), (p) => p.style = s.name));
            if (s.name != StyleSheet.BASIC) {
                var del = icon ("user-trash-symbolic", _("Delete Style"));
                del.clicked.connect (() => {
                    win.edit (_("Delete Style"), () => {
                        string fallback = s.based_on != "" ? s.based_on : StyleSheet.BASIC;
                        pub.styles.paragraph.remove (s);
                        foreach (var o in pub.styles.paragraph) {
                            if (o.based_on == s.name) o.based_on = fallback;
                            if (o.next == s.name) o.next = "";
                        }
                        foreach (var story in pub.stories.values) foreach (var p in story.paras) if (p.style == s.name) p.style = fallback;
                    });
                    rebuild ();
                });
                row.add_suffix (del);
            } else {
                var keep = icon ("user-trash-symbolic", "");
                keep.opacity = 0;
                keep.sensitive = false;
                keep.can_target = false;
                keep.can_focus = false;
                row.add_suffix (keep);
            }
            pg.add_row (row);
        }

        private void redefine_style () {
            var p = win.current_paragraph ();
            if (p == null) return;
            var st = pub.styles.find_paragraph (p.style);
            if (st == null) return;
            var cf = win.current_chars ();
            var base_pf = ParaFormat.defaults ();
            var base_cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (p.style, base_pf, base_cf);
            win.edit (_("Redefine Style"), () => {
                st.para.apply (p.fmt);
                if (cf.font != base_cf.font) st.chars.font = cf.font;
                if (Math.fabs (cf.size - base_cf.size) > 0.01) st.chars.size = cf.size;
                if (cf.bold != base_cf.bold) st.chars.bold = cf.bold;
                if (cf.italic != base_cf.italic) st.chars.italic = cf.italic;
                if (cf.color != base_cf.color) st.chars.color = cf.color;
                foreach (var story in pub.stories.values) foreach (var q in story.paras) if (q.style == st.name) {
                    q.fmt = new ParaFormat ();
                    foreach (var r in q.runs) r.fmt = new CharFormat ();
                }
            });
            rebuild ();
        }
    }

    public class SwatchesPanel : Panel {
        public SwatchesPanel (PublishWindow win) {
            base (win);
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            var g = group (_("Swatches"), pub.settings.cmyk ? _("This is a CMYK job; RGB swatches are flagged by preflight") : _("This is an RGB job"));
            header_button (g, _("New Tint"), () => TypographyDialogs.new_tint (win));
            header_button (g, _("New"), () => Dialogs.edit_swatch (win, null, null));
            var sgroups = new Gee.ArrayList<string> ();
            foreach (var sw in pub.swatches) if (sw.group != "" && !sgroups.contains (sw.group)) sgroups.add (sw.group);
            var order = new Gee.ArrayList<Swatch> ();
            foreach (var sw in pub.swatches) if (sw.group == "") order.add (sw);
            foreach (string gname in sgroups) foreach (var sw in pub.swatches) if (sw.group == gname) order.add (sw);
            PreferencesGroup target = g;
            string current_group = "";
            foreach (var sw in order) {
                var s = sw;
                if (s.group != current_group) {
                    current_group = s.group;
                    target = group (s.group, _("Swatch group"));
                }
                var row = new ActionRow (s.name, "%s%s".printf (s.describe (), s.spot ? ", " + _("spot colour") : (s.model == ColorModel.CMYK ? ", " + _("process") : "")));
                var chip = new DrawingArea ();
                chip.set_size_request (24, 24);
                chip.valign = Align.CENTER;
                chip.margin_end = 8;
                chip.set_draw_func ((d, cr, w, h) => {
                    var c = s.rgba ();
                    Renderer.round_rect (cr, 1, 1, w - 2, h - 2, 5);
                    cr.set_source_rgba (c.r, c.g, c.b, 1);
                    cr.fill_preserve ();
                    cr.set_source_rgba (0, 0, 0, 0.2);
                    cr.set_line_width (1);
                    cr.stroke ();
                });
                row.add_prefix (chip);
                bool fixed_sw = s.name == "Paper" || s.name == "Black" || s.name == "Registration";
                if (!fixed_sw) {
                    var ed = icon ("document-edit-symbolic", _("Edit Swatch"));
                    ed.clicked.connect (() => Dialogs.edit_swatch (win, s, null));
                    row.add_suffix (ed);
                    var del = icon ("user-trash-symbolic", _("Delete Swatch"));
                    del.clicked.connect (() => {
                        if (pub.swatch_in_use (s.name)) {
                            var dlg = new ConfirmDialog (win.app, _("Delete a Swatch in Use?"), "dialog-warning",
                                _("Objects and text that use \"%s\" will turn black.").printf (s.name), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
                            dlg.transient_for = win;
                            dlg.response.connect ((r) => {
                                if (r != ConfirmDialog.Response.PRIMARY) return;
                                win.edit (_("Delete Swatch"), () => pub.swatches.remove (s));
                                rebuild ();
                            });
                            dlg.present ();
                            return;
                        }
                        win.edit (_("Delete Swatch"), () => pub.swatches.remove (s));
                        rebuild ();
                    });
                    row.add_suffix (del);
                } else {
                    for (int k = 0; k < 2; k++) {
                        var keep = icon ("user-trash-symbolic", "");
                        keep.opacity = 0;
                        keep.sensitive = false;
                        keep.can_target = false;
                        keep.can_focus = false;
                        row.add_suffix (keep);
                    }
                }
                var apply = icon ("color-select-symbolic", _("Apply as Fill"));
                apply.clicked.connect (() => {
                    if (win.canvas.edit != null) {
                        win.format_runs (_("Text Colour"), (r) => r.fmt.color = ColorRef.swatch (s.name));
                        return;
                    }
                    if (win.canvas.selection.size == 0) return;
                    win.edit (_("Fill"), () => {
                        foreach (var it in win.canvas.selection) it.fill = new Fill.solid (ColorRef.swatch (s.name));
                    });
                });
                row.add_suffix (apply);
                target.add_row (row);
            }
            var ug = group (_("Unused Swatches"));
            var ur = new ActionRow (_("Remove Unused"), _("Delete swatches no object or text uses"));
            var ub = new Button.with_label (_("Remove"));
            ub.valign = Align.CENTER;
            ub.clicked.connect (() => {
                int n = 0;
                win.edit (_("Remove Unused Swatches"), () => {
                    var dead = new Gee.ArrayList<Swatch> ();
                    foreach (var s in pub.swatches) {
                        if (s.name == "Paper" || s.name == "Black" || s.name == "Registration") continue;
                        if (!pub.swatch_in_use (s.name)) dead.add (s);
                    }
                    n = dead.size;
                    pub.swatches.remove_all (dead);
                });
                win.toast (ngettext ("Removed %d swatch", "Removed %d swatches", n).printf (n));
                rebuild ();
            });
            ur.add_suffix (ub);
            ug.add_row (ur);
        }
    }

    public class LayersPanel : Box {
        private LayerList layers;

        public LayersPanel (PublishWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            layers = new LayerList (win);
            layers.margin_start = layers.margin_end = 14;
            layers.margin_bottom = 12;
            append (layers);
        }

        public void rebuild () {
            layers.rebuild ();
        }
    }

    public class LinksPanel : Panel {
        public LinksPanel (PublishWindow win) {
            base (win);
        }

        private void linked_stories_group () {
            var stories = new Gee.ArrayList<Story> ();
            foreach (var st in pub.stories.values) if (st.link_path != "") stories.add (st);
            if (stories.size == 0) return;
            var g = group (_("Linked Stories"), _("Text edited separately by writers, as with InCopy"));
            foreach (var story in stories) {
                var st = story;
                bool mod = LinkedStory.modified (pub, st);
                var row = new ActionRow (Path.get_basename (st.link_path), mod ? _("Modified by the writer") : _("Up to date"));
                var up = icon ("view-refresh-symbolic", _("Update from the Story File"));
                up.sensitive = mod;
                up.clicked.connect (() => {
                    try {
                        win.doc.checkpoint (_("Update Story"));
                        LinkedStory.update (pub, st);
                        win.doc.touch ();
                        win.canvas.invalidate ();
                    } catch (Error e) {
                        win.show_error (_("Could Not Update the Story"), e.message);
                    }
                    rebuild ();
                });
                row.add_suffix (up);
                var push = icon ("document-send-symbolic", _("Send Layout Changes to the Story File"));
                push.clicked.connect (() => {
                    try {
                        LinkedStory.write_back (pub, st);
                        win.toast (_("The story file was updated"));
                    } catch (Error e) {
                        win.show_error (_("Could Not Write the Story"), e.message);
                    }
                    rebuild ();
                });
                row.add_suffix (push);
                var unlink = icon ("edit-clear-symbolic", _("Unlink"));
                unlink.clicked.connect (() => {
                    win.edit (_("Unlink Story"), () => {
                        st.link_path = "";
                        st.link_stamp = "";
                    });
                    rebuild ();
                });
                row.add_suffix (unlink);
                g.add_row (row);
            }
        }

        private void linked_tables_group () {
            var tables = new Gee.ArrayList<TableItem> ();
            pub.walk ((r) => {
                var t = r.item as TableItem;
                if (t != null && t.link_path != "") tables.add (t);
                return true;
            });
            if (tables.size == 0) return;
            var g = group (_("Linked Spreadsheets"), ngettext ("%d table", "%d tables", tables.size).printf (tables.size));
            header_button (g, _("Update All"), () => {
                int n = 0;
                win.edit (_("Update Linked Tables"), () => n = LinkedTables.update_all (pub));
                win.canvas.invalidate ();
                win.toast (ngettext ("Updated %d table", "Updated %d tables", n).printf (n));
                rebuild ();
            });
            foreach (var t in tables) {
                var tb = t;
                string state = LinkedTables.missing (pub, tb) ? _("Missing") : (LinkedTables.modified (pub, tb) ? _("Modified") : _("Up to date"));
                var row = new ActionRow (Path.get_basename (tb.link_path), state);
                var up = icon ("view-refresh-symbolic", _("Update from the Spreadsheet"));
                up.sensitive = !LinkedTables.missing (pub, tb);
                up.clicked.connect (() => {
                    try {
                        win.doc.checkpoint (_("Update Linked Table"));
                        LinkedTables.update (pub, tb);
                        win.doc.touch ();
                        win.canvas.invalidate ();
                    } catch (Error e) {
                        win.show_error (_("Could Not Update the Table"), e.message);
                    }
                    rebuild ();
                });
                row.add_suffix (up);
                g.add_row (row);
            }
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            linked_tables_group ();
            linked_stories_group ();
            var images = new Gee.ArrayList<ItemRef> ();
            pub.walk ((r) => {
                if (r.item is ImageFrame && ((ImageFrame) r.item).has_image ()) images.add (r);
                return true;
            });
            if (images.size == 0) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                wp.title = _("No Pictures Yet");
                wp.subtitle = _("Placed pictures appear here with their status");
                wp.add_action ("image-x-generic", _("Place Pictures"), _("Link or embed images in frames"), () => win.run ("place"));
                content.append (wp);
                return;
            }
            int missing = 0, modified = 0;
            foreach (var r in images) {
                var st = ImageStore.status (pub, (ImageFrame) r.item);
                if (st == LinkStatus.MISSING) missing++;
                if (st == LinkStatus.MODIFIED) modified++;
            }
            string summary = ngettext ("%d picture", "%d pictures", images.size).printf (images.size);
            if (missing > 0) summary += ", " + ngettext ("%d missing", "%d missing", missing).printf (missing);
            if (modified > 0) summary += ", " + ngettext ("%d modified", "%d modified", modified).printf (modified);
            var g = group (_("Links"), summary);
            if (modified > 0) header_button (g, _("Update All"), () => {
                win.edit (_("Update Links"), () => {
                    foreach (var r in images) {
                        var im = (ImageFrame) r.item;
                        if (ImageStore.status (pub, im) == LinkStatus.MODIFIED) im.link_stamp = ImageStore.stamp_for (ImageStore.resolve_link (pub, im.link));
                    }
                });
                ImageStore.get_default ().clear ();
                rebuild ();
            });
            foreach (var r in images) {
                var im = (ImageFrame) r.item;
                var st = ImageStore.status (pub, im);
                string where = r.page != null ? _("Page %s").printf (pub.page_label (pub.pages.index_of (r.page))) : (r.master != null ? r.master.display_name () : "");
                string name = im.link != "" ? Path.get_basename (im.link) : _("Embedded picture");
                var inf = ImageStore.get_default ().info (pub, im);
                string res = "";
                if (inf != null) {
                    var pl = ImageStore.place (im, inf);
                    res = ", %d ppi".printf ((int) Math.round (double.min (pl.ppi_x (), pl.ppi_y ())));
                }
                var row = new ActionRow (name, "%s, %s%s".printf (ImageStore.status_label (st), where, res));
                string icon_name = st == LinkStatus.MISSING ? "dialog-error-symbolic" : (st == LinkStatus.MODIFIED ? "dialog-warning-symbolic" : (st == LinkStatus.EMBEDDED ? "package-x-generic-symbolic" : "emblem-ok-symbolic"));
                var ic = new Image.from_icon_name (icon_name);
                ic.margin_end = 6;
                row.add_prefix (ic);
                var go = icon ("find-location-symbolic", _("Go to Picture"));
                go.clicked.connect (() => {
                    if (r.page != null) win.go_to_page (pub.pages.index_of (r.page));
                    else if (r.master != null) win.set_master_mode (true, r.master.id);
                    win.canvas.select_only (r.group != null ? (Item) r.group : (Item) im);
                });
                row.add_suffix (go);
                if (im.link != "") {
                    var rl = icon ("insert-link-symbolic", _("Relink"));
                    rl.clicked.connect (() => win.relink.begin (im));
                    row.add_suffix (rl);
                    if (st == LinkStatus.MODIFIED) {
                        var up = icon ("view-refresh-symbolic", _("Update Link"));
                        up.clicked.connect (() => {
                            win.update_link (im);
                            rebuild ();
                        });
                        row.add_suffix (up);
                    }
                    if (st != LinkStatus.MISSING) {
                        var em = icon ("package-x-generic-symbolic", _("Embed"));
                        em.clicked.connect (() => win.embed_image (im));
                        row.add_suffix (em);
                    }
                } else {
                    var un = icon ("document-save-symbolic", _("Unembed"));
                    un.clicked.connect (() => win.unembed_image (im));
                    row.add_suffix (un);
                }
                g.add_row (row);
            }
        }
    }

    public class PreflightPanel : Panel {
        public int mode = 0;

        public PreflightPanel (PublishWindow win) {
            base (win);
        }

        public static PreflightProfile active_profile (PublishWindow w, string over = "") {
            var pub = w.doc.pub;
            var p = PreflightProfile.find (pub, over != "" ? over : pub.preflight_profile).clone ();
            if (p.builtin && p.name == PreflightProfile.BASIC) p.min_ppi = w.app.get_int ("preflight-min-ppi", 250);
            return p;
        }

        public static Preflight prepare (PublishWindow w, string over = "") {
            var pf = new Preflight (w.doc.pub);
            pf.use_profile (active_profile (w, over));
            return pf;
        }

        public Preflight make () {
            string over = mode == 1 ? PreflightProfile.PRINT : (mode == 2 ? PreflightProfile.ACCESSIBLE : "");
            return prepare (win, over);
        }

        public override void rebuild () {
            if (win.doc == null) {
                clear ();
                return;
            }
            var pf = make ();
            pf.run ();
            show_issues (pf);
        }

        public void show_issues (Preflight pf) {
            clear ();
            var profiles = PreflightProfile.all (pub);
            string[] names = {};
            foreach (var p in profiles) names += PreflightProfile.display_name (p.name);
            var pg = group (_("Profile"), pf.profile.description != "" ? pf.profile.description : null);
            var pick = new SelectionRow (_("Check With"), names, PreflightProfile.display_name (pf.profile.name));
            pick.selected.connect ((label) => {
                foreach (var p in profiles) {
                    if (PreflightProfile.display_name (p.name) != label) continue;
                    string chosen = p.name;
                    mode = 0;
                    win.edit (_("Preflight Profile"), () => pub.preflight_profile = chosen);
                    Idle.add (() => {
                        rebuild ();
                        win.schedule_preflight ();
                        return Source.REMOVE;
                    });
                }
            });
            pg.add_row (pick);
            header_button (pg, _("Profiles…"), () => PreflightProfiles.manage (win, pf.profile.name));
            int errors = pf.count (Severity.ERROR), warns = pf.count (Severity.WARNING), infos = pf.count (Severity.INFO);
            if (errors == 0 && warns == 0) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                bool a11y_only = !pf.profile.links && pf.profile.accessibility;
                wp.title = a11y_only ? _("Accessibility Checker") : _("Design Checker");
                if (a11y_only) wp.subtitle = infos > 0 ? ngettext ("Accessible, with %d note", "Accessible, with %d notes", infos).printf (infos) : _("No problems found: alternative text, contrast, tables, links and title are fine");
                else wp.subtitle = infos > 0 ? ngettext ("Ready for print, with %d note", "Ready for print, with %d notes", infos).printf (infos) : _("No problems found: links, resolution, text, fonts, colours and bleed are fine");
                wp.add_action ("x-office-document", _("Export PDF"), _("Create a print-ready PDF with bleed and marks"), () => win.run ("export-pdf"));
                wp.add_action ("folder", _("Package"), _("Collect the publication and its pictures in a folder"), () => win.run ("package"));
                content.append (wp);
            }
            var cats = new Gee.ArrayList<string> ();
            foreach (var i in pf.issues) if (!cats.contains (i.category ())) cats.add (i.category ());
            foreach (string cat in cats) {
                int n = 0;
                foreach (var i in pf.issues) if (i.category () == cat) n++;
                var g = group (cat, ngettext ("%d item", "%d items", n).printf (n));
                foreach (var i in pf.issues) {
                    if (i.category () != cat) continue;
                    var issue = i;
                    string where = i.page >= 0 ? _("Page %s").printf (pub.page_label (i.page)) : (i.item >= 0 ? _("Master page") : _("Document"));
                    var row = new ActionRow (i.message, where);
                    string ic = i.severity == Severity.ERROR ? "dialog-error-symbolic" : (i.severity == Severity.WARNING ? "dialog-warning-symbolic" : "dialog-information-symbolic");
                    var pic = new Image.from_icon_name (ic);
                    pic.margin_end = 6;
                    row.add_prefix (pic);
                    if (i.item >= 0) {
                        var go = icon ("find-location-symbolic", _("Show"));
                        go.clicked.connect (() => reveal (issue));
                        row.add_suffix (go);
                    }
                    g.add_row (row);
                }
            }
            var sg = group (_("Checks"), PreflightProfiles.summary (pf.profile));
            var rr = new ActionRow (_("Run Again"));
            var b = new Button.with_label (_("Check"));
            b.valign = Align.CENTER;
            b.clicked.connect (() => rebuild ());
            rr.add_suffix (b);
            sg.add_row (rr);
        }

        private void reveal (PreflightIssue i) {
            var r = pub.find_item (i.item);
            if (r == null) return;
            if (r.page != null) win.go_to_page (pub.pages.index_of (r.page));
            else if (r.master != null) win.set_master_mode (true, r.master.id);
            win.canvas.select_only (r.group != null ? (Item) r.group : r.item);
        }
    }

    public class MergePanel : Panel {
        public MergePanel (PublishWindow win) {
            base (win);
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            var m = pub.merge;
            if (!m.active ()) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                wp.title = _("Mail Merge");
                wp.subtitle = _("Make one copy per record for letters, labels, cards and catalogues");
                wp.add_action ("x-office-spreadsheet", _("Use a CSV File"), _("Columns become merge fields"), () => choose_csv ());
                wp.add_action ("x-office-spreadsheet", _("Use a Spreadsheet"), _("A sheet from an XLSX or ODS workbook"), () => win.run ("merge-sheet"));
                wp.add_action ("x-office-database", _("Use a Database"), _("A table or query from a database file"), () => win.run ("merge-database"));
                wp.add_action ("x-office-addressbook", _("Use Contacts"), _("Names, addresses, e-mails and photos"), () => use_contacts ());
                wp.add_action ("document-new", _("Type a New List"), _("Enter the records by hand"), () => win.run ("merge-new-list"));
                content.append (wp);
                return;
            }
            string src = m.source_kind == "contacts" ? _("Contacts") : Path.get_basename (m.source_path);
            var sg = group (_("Data Source"), _("%s, %d records").printf (src, m.records.size));
            header_button (sg, _("Remove"), () => win.run ("merge-remove"));
            var rl = new ActionRow (_("Recipients"), _("%d of %d records selected").printf (m.selected_records ().size, m.records.size));
            var rlb = new Button.with_label (_("Edit…"));
            rlb.valign = Align.CENTER;
            rlb.clicked.connect (() => win.run ("merge-recipients"));
            rl.add_suffix (rlb);
            sg.add_row (rl);
            if (m.source_kind == "csv" && m.source_path != "") {
                var rr = new ActionRow (_("Refresh"), _("Read the file again"));
                var rb = new Button.with_label (_("Refresh"));
                rb.valign = Align.CENTER;
                rb.clicked.connect (() => load_csv (m.source_path));
                rr.add_suffix (rb);
                sg.add_row (rr);
            }
            var fg = group (_("Fields"), _("Insert at the text cursor, or pick a picture field for the selected image frame"));
            foreach (string f in m.fields) {
                string ff = f;
                string sample = m.records.size > 0 ? m.value (int.max (0, m.preview), f) : "";
                var row = new ActionRow (f, sample.length > 40 ? sample.substring (0, sample.index_of_nth_char (40)) + "…" : sample);
                if (Merge.image_field (pub, f)) row.subtitle = _("Picture field: %s").printf (row.subtitle ?? "");
                var ins = icon ("insert-text-symbolic", _("Insert Field"));
                ins.clicked.connect (() => insert_field (ff));
                row.add_suffix (ins);
                var img = icon ("insert-image-symbolic", _("Use as Picture Field"));
                img.clicked.connect (() => {
                    var im = win.single_image ();
                    if (im == null) {
                        win.toast (_("Select an image frame first"));
                        return;
                    }
                    win.edit (_("Picture Field"), () => im.merge_field = ff);
                });
                row.add_suffix (img);
                fg.add_row (row);
            }
            var rg = group (_("Placement Rules"), _("Applied to every record when the publication is merged"));
            string[] fits = { _("As Set on Each Frame"), _("Fill the Frame"), _("Fit Inside the Frame"), _("Stretch to the Frame") };
            var fit = new SelectionRow (_("Picture Fitting"), fits, fits[(m.image_fit + 1).clamp (0, 3)]);
            fit.selected.connect ((label) => {
                for (int i = 0; i < fits.length; i++) if (fits[i] == label) {
                    int v = i - 1;
                    win.edit (_("Picture Fitting"), () => m.image_fit = v);
                }
            });
            rg.add_row (fit);
            var hide = new SwitchRow (_("Hide Frames Without a Picture"), _("When the file named in the record is missing"), m.hide_missing_images);
            hide.switch_btn.notify["active"].connect (() => {
                bool v = hide.switch_btn.active;
                if (v != m.hide_missing_images) win.edit (_("Placement Rules"), () => m.hide_missing_images = v);
            });
            rg.add_row (hide);
            var blank = new SwitchRow (_("Remove Blank Lines"), _("Drop paragraphs whose fields are all empty"), m.remove_blank_lines);
            blank.switch_btn.notify["active"].connect (() => {
                bool v = blank.switch_btn.active;
                if (v != m.remove_blank_lines) win.edit (_("Placement Rules"), () => m.remove_blank_lines = v);
            });
            rg.add_row (blank);
            var pg = group (_("Preview"));
            var prev_toggle = new SwitchRow (_("Preview Results"), _("Show a record in place of the fields"), m.preview >= 0);
            prev_toggle.switch_btn.notify["active"].connect (() => {
                bool v = prev_toggle.switch_btn.active;
                if ((m.preview >= 0) == v) return;
                m.preview = v ? 0 : -1;
                win.content_edited ();
                rebuild ();
            });
            pg.add_row (prev_toggle);
            if (m.preview >= 0) {
                var nav = new ActionRow (_("Record %d of %d").printf (m.preview + 1, m.records.size));
                var first = icon ("go-first-symbolic", _("First Record"));
                first.clicked.connect (() => go (0));
                var prev = icon ("go-previous-symbolic", _("Previous Record"));
                prev.clicked.connect (() => step (-1));
                var next = icon ("go-next-symbolic", _("Next Record"));
                next.clicked.connect (() => step (1));
                var last = icon ("go-last-symbolic", _("Last Record"));
                last.clicked.connect (() => go (m.records.size - 1));
                nav.add_suffix (first);
                nav.add_suffix (prev);
                nav.add_suffix (next);
                nav.add_suffix (last);
                pg.add_row (nav);
            }
            var cg = group (_("Catalogue Merge"), _("Repeat the objects inside an area once per record, in a grid"));
            var ct = new SwitchRow (_("Catalogue Merge"), null, m.catalogue);
            ct.switch_btn.notify["active"].connect (() => {
                bool v = ct.switch_btn.active;
                if (v == m.catalogue) return;
                win.edit (_("Catalogue Merge"), () => m.catalogue = v);
                rebuild ();
                win.canvas.queue_draw ();
            });
            cg.add_row (ct);
            if (m.catalogue) {
                var rows = new SpinRow (_("Rows"), null, 1, 50, 1, m.cat_rows);
                rows.spin_btn.value_changed.connect (() => win.edit (_("Catalogue"), () => m.cat_rows = (int) rows.spin_btn.value, "cat-rows"));
                cg.add_row (rows);
                var cols = new SpinRow (_("Columns"), null, 1, 50, 1, m.cat_cols);
                cols.spin_btn.value_changed.connect (() => win.edit (_("Catalogue"), () => m.cat_cols = (int) cols.spin_btn.value, "cat-cols"));
                cg.add_row (cols);
                var area = new ActionRow (_("Repeating Area"), "%s × %s".printf (Units.format (m.cat_w, pub.settings.units), Units.format (m.cat_h, pub.settings.units)));
                var ab = new Button.with_label (_("From Selection"));
                ab.valign = Align.CENTER;
                ab.clicked.connect (() => area_from_selection ());
                area.add_suffix (ab);
                cg.add_row (area);
                var gx = new SpinRow (_("Horizontal Gap (pt)"), null, 0, 500, 1, m.cat_gap_x);
                gx.spin_btn.value_changed.connect (() => win.edit (_("Catalogue"), () => m.cat_gap_x = gx.spin_btn.value, "cat-gx"));
                cg.add_row (gx);
                var gy = new SpinRow (_("Vertical Gap (pt)"), null, 0, 500, 1, m.cat_gap_y);
                gy.spin_btn.value_changed.connect (() => win.edit (_("Catalogue"), () => m.cat_gap_y = gy.spin_btn.value, "cat-gy"));
                cg.add_row (gy);
            }
            var og = group (_("Finish"));
            var r1 = new ActionRow (_("Merge to PDF"), _("One copy per record, with bleed and marks as set on export"));
            var b1 = new Button.with_label (_("Export…"));
            b1.add_css_class ("suggested-action");
            b1.valign = Align.CENTER;
            b1.clicked.connect (() => merge_pdf ());
            r1.add_suffix (b1);
            og.add_row (r1);
            var r2 = new ActionRow (_("Merge to New Publication"), _("Open the merged pages for editing"));
            var b2 = new Button.with_label (_("Merge"));
            b2.valign = Align.CENTER;
            b2.clicked.connect (() => merge_new ());
            r2.add_suffix (b2);
            og.add_row (r2);
            var r3 = new ActionRow (_("Print Merged"));
            var b3 = new Button.with_label (_("Print…"));
            b3.valign = Align.CENTER;
            b3.clicked.connect (() => merge_print ());
            r3.add_suffix (b3);
            og.add_row (r3);
            var r4 = new ActionRow (_("Merge to Email"), _("One message per record, addressed from a field"));
            var b4 = new Button.with_label (_("Email…"));
            b4.valign = Align.CENTER;
            b4.clicked.connect (() => win.run ("merge-email"));
            r4.add_suffix (b4);
            og.add_row (r4);
        }

        private void insert_field (string f) {
            if (win.canvas.edit == null) {
                win.toast (_("Click in a text frame to place the field"));
                return;
            }
            win.canvas.insert_field (Fields.merge (f));
        }

        public void go (int i) {
            var m = pub.merge;
            if (!m.active () || m.records.size == 0) return;
            m.preview = i.clamp (0, m.records.size - 1);
            win.content_edited ();
            rebuild ();
        }

        public void step (int d) {
            var m = pub.merge;
            go ((m.preview < 0 ? 0 : m.preview) + d);
        }

        public void choose_csv () {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a CSV File");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Comma-Separated Values"), { "csv", "tsv", "txt" }));
            dialog.filters = filters;
            dialog.initial_folder = win.default_folder ();
            dialog.open.begin (win, null, (o, res) => {
                try {
                    var f = dialog.open.end (res);
                    if (f != null && f.get_path () != null) load_csv (f.get_path ());
                } catch (Error e) {
                }
            });
        }

        public void load_csv (string path) {
            try {
                string text;
                FileUtils.get_contents (path, out text);
                if (!text.validate ()) text = convert (text, -1, "UTF-8", "ISO-8859-1");
                var t = Csv.parse (text);
                if (t.fields.size == 0) {
                    win.show_error (_("Could Not Read the File"), _("The file has no columns."));
                    return;
                }
                win.edit (_("Data Source"), () => Merge.set_source (pub, t, "csv", path));
                win.toast (ngettext ("Loaded %d record", "Loaded %d records", t.records.size).printf (t.records.size));
                rebuild ();
                win.toggle_panel ("merge", true);
            } catch (Error e) {
                win.show_error (_("Could Not Read the File"), e.message);
            }
        }

        public void use_contacts () {
            string photos = Path.build_filename (Environment.get_user_cache_dir (), "singularity-publish", "contact-photos");
            var t = VCardReader.load_contacts (null, photos);
            if (t.records.size == 0) {
                win.show_error (_("No Contacts"), _("There are no contacts to merge. Add some in Contacts first."));
                return;
            }
            win.edit (_("Data Source"), () => Merge.set_source (pub, t, "contacts", ""));
            win.toast (ngettext ("Loaded %d contact", "Loaded %d contacts", t.records.size).printf (t.records.size));
            rebuild ();
            win.toggle_panel ("merge", true);
        }

        public void area_from_selection () {
            if (win.canvas.selection.size == 0) {
                win.toast (_("Select the objects that make one catalogue entry"));
                return;
            }
            var b = win.canvas.selection_bounds ();
            win.edit (_("Catalogue Area"), () => {
                pub.merge.catalogue = true;
                pub.merge.cat_x = b.x;
                pub.merge.cat_y = b.y;
                pub.merge.cat_w = b.w;
                pub.merge.cat_h = b.h;
            });
            rebuild ();
            win.canvas.queue_draw ();
        }

        public void merge_pdf () {
            if (!pub.merge.active ()) {
                win.toast (_("Choose a data source first"));
                return;
            }
            var merged = Merge.expand (pub);
            merged.base_dir = pub.base_dir;
            Dialogs.export_pdf (win, merged, win.base_name (_("Merged")) + " " + _("merged"));
        }

        public void merge_new () {
            if (!pub.merge.active ()) {
                win.toast (_("Choose a data source first"));
                return;
            }
            var merged = Merge.expand (pub);
            merged.base_dir = pub.base_dir;
            var d = new Document (merged);
            var nw = new PublishWindow (win.app);
            nw.present ();
            nw.load_document (d);
        }

        public void merge_print () {
            if (!pub.merge.active ()) {
                win.toast (_("Choose a data source first"));
                return;
            }
            var merged = Merge.expand (pub);
            merged.base_dir = pub.base_dir;
            win.print_publication (merged);
        }
    }
}
