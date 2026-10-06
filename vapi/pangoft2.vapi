[CCode (cheader_filename = "pango/pangofc-font.h", lower_case_cprefix = "pango_fc_")]
namespace PangoFc {
    [CCode (cname = "pango_fc_font_get_pattern")]
    public unowned Fc.Pattern? font_pattern (Pango.Font font);
    [CCode (cname = "pango_fc_font_get_type")]
    public GLib.Type font_type ();
}
