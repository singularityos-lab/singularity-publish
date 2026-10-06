using Singularity.Apps.Publish;

const double A4_W = 595.28;
const double A4_H = 841.89;

Publication card (int pages, double bleed) {
    var s = new DocSettings ();
    s.width = 255.1;
    s.height = 155.9;
    s.set_margins (10);
    s.set_bleed (bleed);
    return Publication.create (s, pages);
}

Singularity.Print.PageFormat a4 () {
    var f = new Singularity.Print.PageFormat ();
    f.width = A4_W;
    f.height = A4_H;
    return f;
}

int run_paginate (PublishPrintSource src, Singularity.Print.PageFormat f) {
    var loop = new MainLoop ();
    int n = -1;
    src.paginate.begin (f, (o, r) => {
        try {
            n = src.paginate.end (r);
        } catch (Error e) {
            error ("paginate failed: %s", e.message);
        }
        loop.quit ();
    });
    loop.run ();
    return n;
}

void test_options () {
    var p = card (3, 8.5);
    p.settings.impose = "nup:2x5:a4";
    var x = PublishPrintSource.prepress_options (p, null);
    assert (x.get_choice ("imposition") == "nup");
    assert (x.get_number ("across") == 2 && x.get_number ("down") == 5);
    assert (x.get_bool ("crop-marks") && x.get_bool ("step-repeat"));
    assert (!x.get_bool ("bleed"));
    assert (x.is_visible ("across") && !x.is_visible ("bleed-marks"));
    x.set_choice ("imposition", "none");
    assert (!x.is_visible ("across") && x.is_visible ("bleed-marks"));
    assert (x.find ("colour") != null && x.find ("colour").kind == Singularity.Print.ExtraKind.NOTE);
    var o = PublishPrintSource.options_for (x, A4_W, A4_H, { 0, 2 });
    assert (o.impose == ImposeMode.NONE && o.ranges == "1, 3");
    x.set_choice ("imposition", "booklet");
    o = PublishPrintSource.options_for (x, A4_W, A4_H, {});
    assert (o.impose == ImposeMode.BOOKLET && o.sheet_w > o.sheet_h && o.ranges == "");
}

void test_single_pages_with_marks () {
    var p = card (3, 8.5);
    var src = new PublishPrintSource (p, "Cards", 1);
    assert (src.imposes_pages && src.document_pages == 3 && src.current_page == 1);
    var x = src.extra_options;
    x.set_choice ("imposition", "none");
    x.set_bool ("crop-marks", false);
    assert (run_paginate (src, a4 ()) == 3);
    assert ((src.page_width - 255.1).abs () < 0.01 && (src.page_height - 155.9).abs () < 0.01);
    x.set_bool ("bleed", true);
    run_paginate (src, a4 ());
    assert ((src.page_width - (255.1 + 17)).abs () < 0.01);
    x.set_bool ("crop-marks", true);
    run_paginate (src, a4 ());
    double m = 6 + 18;
    assert ((src.page_width - (255.1 + 17 + 2 * m)).abs () < 0.01);
    assert ((src.page_height - (155.9 + 17 + 2 * m)).abs () < 0.01);
    src.page_selection = { 0, 2 };
    assert (run_paginate (src, a4 ()) == 2);
    assert (src.sheets[0].slots[0].page == 0 && src.sheets[1].slots[0].page == 2);
}

void test_nup_on_dialog_paper () {
    var p = card (5, 0);
    var src = new PublishPrintSource (p, "Cards", 0);
    var x = src.extra_options;
    x.set_choice ("imposition", "nup");
    x.set_number ("across", 2);
    x.set_number ("down", 2);
    x.set_bool ("step-repeat", false);
    assert (run_paginate (src, a4 ()) == 2);
    assert (src.sheets[0].slots.size == 4 && src.sheets[1].slots.size == 1);
    assert ((src.page_width - A4_W).abs () < 0.01 || (src.page_width - A4_H).abs () < 0.01);
    foreach (var sl in src.sheets[0].slots) {
        assert (sl.x >= 0 && sl.y >= 0);
        assert (sl.x + sl.w <= src.sheets[0].w + 0.01 && sl.y + sl.h <= src.sheets[0].h + 0.01);
    }
    x.set_bool ("step-repeat", true);
    x.set_number ("down", 5);
    assert (run_paginate (src, a4 ()) == 5);
    foreach (var sl in src.sheets[3].slots) assert (sl.page == 3);
    var f = a4 ();
    f.width = A4_H;
    f.height = A4_W;
    run_paginate (src, f);
    assert (src.sheets[0].w * src.sheets[0].h > 0);
}

void test_booklet () {
    var p = card (5, 0);
    var src = new PublishPrintSource (p, "Folded", 0);
    var x = src.extra_options;
    x.set_choice ("imposition", "booklet");
    assert (run_paginate (src, a4 ()) == 4);
    assert (src.sheets[0].w > src.sheets[0].h);
    assert (src.sheets[0].slots.size == 1 && src.sheets[0].slots[0].page == 0);
    assert (src.sheets[1].slots.size == 1 && src.sheets[1].slots[0].page == 1);
    assert (src.sheets[3].slots.size == 2 && src.sheets[3].slots[0].page == 3 && src.sheets[3].slots[1].page == 4);
}

void test_pdf_through_sheet_renderer () {
    var p = card (4, 8.5);
    var src = new PublishPrintSource (p, "Cards", 0);
    var x = src.extra_options;
    x.set_choice ("imposition", "nup");
    x.set_bool ("step-repeat", false);
    x.set_bool ("bleed", true);
    x.set_bool ("crop-marks", true);
    int n = run_paginate (src, a4 ());
    var opts = new Singularity.Print.JobOptions ();
    var r = new Singularity.Print.SheetRenderer (src, opts);
    var spec = new Singularity.Print.LayoutSpec ();
    spec.page_width = src.page_width;
    spec.page_height = src.page_height;
    spec.sheet_width = A4_W;
    spec.sheet_height = A4_H;
    int[] pages = {};
    for (int i = 0; i < n; i++) pages += i;
    var sides = Singularity.Print.Imposition.impose (pages, spec);
    assert (sides.size == 1);
    string path = Path.build_filename (Environment.get_tmp_dir (), "publish-print-%lld.pdf".printf (get_monotonic_time ()));
    try {
        r.write_pdf (path, sides);
    } catch (Error e) {
        error ("pdf: %s", e.message);
    }
    assert (FileUtils.test (path, FileTest.EXISTS));
    FileUtils.remove (path);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    test_options ();
    print ("ok 1 prepress options\n");
    test_single_pages_with_marks ();
    print ("ok 2 single pages, bleed and marks\n");
    test_nup_on_dialog_paper ();
    print ("ok 3 several per sheet on the dialog paper\n");
    test_booklet ();
    print ("ok 4 booklet\n");
    test_pdf_through_sheet_renderer ();
    print ("ok 5 pdf through the dialog renderer\n");
    return 0;
}
