using Singularity.Apps.Publish;

void pump () {
    var ctx = MainContext.default ();
    for (int i = 0; i < 400 && ctx.pending (); i++) ctx.iteration (false);
}

void reset (PublishWindow win) {
    if (win.doc != null) {
        win.doc.modified = false;
        win.doc.path = null;
    }
}

void act (PublishWindow win, string name, Variant? param = null) {
    win.activate_action_variant ("win." + name, param);
    pump ();
}

TextFrame first_frame (Publication p, int page) {
    foreach (var it in p.pages[page].items) if (it is TextFrame) return (TextFrame) it;
    assert_not_reached ();
}

void test_templates_load (PublishWindow win) {
    foreach (var t in Templates.all ()) {
        win.new_from_template (t.id);
        pump ();
        assert (win.doc != null && win.doc.pub.pages.size >= 1);
        foreach (string panel in new string[] { "format", "styles", "swatches", "layers", "links", "preflight", "merge" }) {
            win.toggle_panel (panel, true);
            pump ();
        }
        win.go_to_page (win.doc.pub.pages.size - 1);
        pump ();
        win.set_master_mode (true);
        pump ();
        win.set_master_mode (false);
        pump ();
        win.doc.modified = false;
    }
}

void test_text_editing (PublishWindow win) {
    var s = new DocSettings ();
    reset (win);
    win.new_blank (s, 2);
    pump ();
    win.canvas.sel_page = 0;
    act (win, "insert-text");
    assert (win.canvas.edit != null);
    win.canvas.insert_text ("Hello publishing world");
    pump ();
    var story = win.canvas.edit.story;
    assert (story.plain_text () == "Hello publishing world");
    win.canvas.edit.anchor = TextPos (0, 0);
    win.canvas.edit.caret = TextPos (0, 5);
    act (win, "bold");
    assert (story.format_at (TextPos (0, 2)).fmt.bold == 1);
    act (win, "align-center");
    assert (story.paras[0].fmt.align == (int) TextAlign.CENTER);
    act (win, "undo");
    act (win, "undo");
    assert (story.format_at (TextPos (0, 2)).fmt.bold != 1 || win.doc.pub.story (story.id).format_at (TextPos (0, 2)).fmt.bold != 1);
    act (win, "redo");
    win.canvas.clear_selection ();
    pump ();
    var f = first_frame (win.doc.pub, 0);
    win.canvas.select_only (f);
    win.canvas.begin_edit (f);
    win.canvas.insert_field (Fields.PAGE);
    assert (win.doc.pub.story (f.story).fields ().contains (Fields.PAGE));
    act (win, "select-all");
    act (win, "copy");
    win.canvas.end_edit ();
    act (win, "drop-cap");
    act (win, "bullets");
    act (win, "hyphenate");
    act (win, "align-grid");
    act (win, "font-bigger");
    act (win, "superscript");
    act (win, "all-caps");
    act (win, "clear-overrides");
}

void test_objects (PublishWindow win) {
    reset (win);
    win.new_blank (new DocSettings (), 3);
    pump ();
    var p = win.doc.pub;
    int before = p.pages[0].items.size;
    foreach (string k in new string[] { "rect", "ellipse", "polygon", "star", "line" }) act (win, "insert-shape", new Variant.string (k));
    if (p.pages[0].items.size != 5) print ("items before %d after %d, pages %d, doc same %s\n", before, p.pages[0].items.size, p.pages.size, (p == win.doc.pub).to_string ());
    assert (p.pages[0].items.size == 5);
    act (win, "select-all");
    assert (win.canvas.selection.size == 5);
    act (win, "arrange-left");
    act (win, "distribute-v");
    act (win, "group");
    assert (p.pages[0].items.size == 1 && p.pages[0].items[0] is GroupItem);
    act (win, "rotate-cw");
    act (win, "ungroup");
    assert (p.pages[0].items.size == 5);
    act (win, "select-all");
    act (win, "copy");
    act (win, "delete");
    assert (p.pages[0].items.size == 0);
    act (win, "undo");
    p = win.doc.pub;
    assert (p.pages[0].items.size == 5);
    act (win, "select-all");
    act (win, "wrap", new Variant.string ("contour"));
    foreach (var it in win.canvas.selection) assert (it.wrap == WrapMode.CONTOUR);
    act (win, "lock");
    act (win, "unlock-all");
    act (win, "bring-front");
    act (win, "send-back");
    act (win, "duplicate");
    assert (p.pages[0].items.size == 10);
    win.insert_table (4, 3, 1);
    pump ();
    var tb = (TableItem) win.canvas.selection[0];
    win.canvas.cell_r1 = win.canvas.cell_r2 = 1;
    win.canvas.cell_c1 = 0;
    win.canvas.cell_c2 = 1;
    act (win, "table-merge");
    assert (tb.cells[1][0].col_span == 2);
    act (win, "table-row-below");
    assert (tb.rows == 5);
    act (win, "add-page");
    assert (p.pages.size == 4);
    act (win, "duplicate-page");
    assert (p.pages.size == 5);
    act (win, "delete-page");
    assert (p.pages.size == 4);
    win.add_pages (0, 2, "A");
    assert (p.pages.size == 6);
    act (win, "new-master");
    assert (p.masters.size == 2);
    win.set_master_mode (false);
    pump ();
}

void test_threading_ui (PublishWindow win) {
    reset (win);
    win.new_blank (new DocSettings (), 2);
    pump ();
    var p = win.doc.pub;
    win.canvas.sel_page = 0;
    act (win, "insert-text");
    var sb = new StringBuilder ();
    for (int i = 0; i < 200; i++) sb.append ("flowing text ");
    win.canvas.insert_text (sb.str);
    var f1 = win.canvas.edit.frame;
    assert (win.canvas.cache.story (f1.story).overset);
    win.canvas.end_edit ();
    win.go_to_page (1);
    act (win, "insert-text");
    var f2 = win.canvas.edit.frame;
    win.canvas.end_edit ();
    win.canvas.select_only (f1);
    act (win, "thread-new");
    assert (win.canvas.thread_from == f1);
    win.canvas.finish_thread (f2);
    assert (f1.story == f2.story);
    assert (p.thread_frames (f1.story).size == 2);
    win.canvas.select_only (f1);
    act (win, "fit-frame");
    act (win, "unthread");
    assert (f1.story != f2.story);
}

void test_images_merge (PublishWindow win, string dir) {
    reset (win);
    win.new_blank (new DocSettings (), 1);
    pump ();
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, 60, 40);
    pb.fill ((uint32) 0x2255aaff);
    string img = Path.build_filename (dir, "photo.png");
    string csv = Path.build_filename (dir, "people.csv");
    try {
        pb.savev (img, "png", null, null);
        FileUtils.set_contents (csv, "Name,City,Photo\nAda,London,%s\nGrace,Arlington,%s\n".printf (img, img));
    } catch (Error e) {
        assert_not_reached ();
    }
    win.place_files ({ File.new_for_path (img) });
    var im = win.single_image ();
    assert (im != null && im.link == img);
    assert (ImageStore.status (win.doc.pub, im) == LinkStatus.OK);
    win.embed_image (im);
    assert (im.media != "" && im.link == "");
    act (win, "fit-fill");
    act (win, "fit-frame-content");
    act (win, "fit-center");
    win.merge_panel.load_csv (csv);
    pump ();
    assert (win.doc.pub.merge.records.size == 2);
    im.merge_field = "Photo";
    act (win, "insert-text");
    win.canvas.insert_field (Fields.merge ("Name"));
    act (win, "merge-preview");
    act (win, "merge-next");
    assert (win.doc.pub.merge.preview == 1);
    var merged = Merge.expand (win.doc.pub);
    assert (merged.pages.size == 2);
    FileUtils.remove (img);
    FileUtils.remove (csv);
}

void test_save_reopen (PublishWindow win, string dir) {
    reset (win);
    win.new_from_template ("newsletter");
    pump ();
    string path = Path.build_filename (dir, "news.spub");
    try {
        win.doc.save_to (path);
        var d = Document.open (path);
        reset (win);
        win.load_document (d);
        pump ();
        assert (win.doc.pub.pages.size == 4);
        string sla = Path.build_filename (dir, "news.sla");
        win.doc.save_to (sla);
        var d2 = Document.open (sla);
        win.load_document (d2);
        pump ();
        assert (win.doc.pub.pages.size == 4);
        FileUtils.remove (sla);
    } catch (Error e) {
        error ("%s", e.message);
    }
    FileUtils.remove (path);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    string? display = Environment.get_variable ("PUBLISH_UI_TEST_DISPLAY");
    if (display == null || display == "") {
        print ("ui test skipped: set PUBLISH_UI_TEST_DISPLAY to a private X display\n");
        return 77;
    }
    Environment.set_variable ("DISPLAY", display, true);
    Environment.unset_variable ("WAYLAND_DISPLAY");
    Environment.set_variable ("GDK_BACKEND", "x11", true);
    if (!Gtk.init_check ()) {
        print ("ui test skipped: no display\n");
        return 77;
    }
    var app = new PublishApp ();
    app.flags = ApplicationFlags.HANDLES_OPEN | ApplicationFlags.NON_UNIQUE;
    try {
        app.register (null);
    } catch (Error e) {
        print ("ui test skipped: %s\n", e.message);
        return 77;
    }
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-ui-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    var win = new PublishWindow (app);
    win.present ();
    pump ();
    int n = 0;
    test_templates_load (win);
    print ("ok %d templates\n", ++n);
    test_text_editing (win);
    print ("ok %d text editing\n", ++n);
    test_objects (win);
    print ("ok %d objects, tables, pages, masters\n", ++n);
    test_threading_ui (win);
    print ("ok %d threading\n", ++n);
    test_images_merge (win, dir);
    print ("ok %d images and mail merge\n", ++n);
    test_save_reopen (win, dir);
    print ("ok %d save and reopen\n", ++n);
    win.doc.modified = false;
    win.destroy ();
    DirUtils.remove (dir);
    print ("ui tests passed (%d)\n", n);
    return 0;
}
