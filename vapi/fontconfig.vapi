[CCode (cheader_filename = "fontconfig/fontconfig.h", lower_case_cprefix = "Fc", cprefix = "Fc")]
namespace Fc {
    [CCode (cname = "FcResult", cprefix = "FcResult", has_type_id = false)]
    public enum Result {
        Match,
        NoMatch,
        TypeMismatch,
        NoId,
        OutOfMemory
    }

    [Compact]
    [CCode (cname = "FcPattern", free_function = "FcPatternDestroy")]
    public class Pattern {
        [CCode (cname = "FcPatternCreate")]
        public Pattern ();
        [CCode (cname = "FcPatternAddString")]
        public bool add_string (string object, string s);
        [CCode (cname = "FcPatternAddInteger")]
        public bool add_integer (string object, int i);
        [CCode (cname = "FcPatternGetString")]
        public Result get_string (string object, int n, out unowned string s);
        [CCode (cname = "FcPatternGetInteger")]
        public Result get_integer (string object, int n, out int i);
        [CCode (cname = "FcPatternGetBool")]
        public Result get_bool (string object, int n, out bool b);
    }

    [Compact]
    [CCode (cname = "FcObjectSet", free_function = "FcObjectSetDestroy")]
    public class ObjectSet {
        [CCode (cname = "FcObjectSetCreate")]
        public ObjectSet ();
        [CCode (cname = "FcObjectSetAdd")]
        public bool add (string object);
    }

    [Compact]
    [CCode (cname = "FcFontSet", free_function = "FcFontSetDestroy")]
    public class FontSet {
        public int nfont;
        [CCode (array_length_cname = "nfont")]
        public unowned Pattern[] fonts;
    }

    [CCode (cname = "FcFontList")]
    public FontSet? font_list (void* config, Pattern p, ObjectSet os);
    [CCode (cname = "FcInit")]
    public bool init ();
}
