namespace Singularity.Apps.Publish {

    public enum FontLicence {
        INSTALLABLE,
        EDITABLE,
        PRINT_PREVIEW,
        RESTRICTED,
        UNKNOWN;

        public bool may_copy () {
            return this != RESTRICTED;
        }

        public string label () {
            switch (this) {
                case INSTALLABLE: return _("installable");
                case EDITABLE: return _("editable embedding");
                case PRINT_PREVIEW: return _("print and preview embedding");
                case RESTRICTED: return _("restricted licence, not copied");
                default: return _("licence not stated");
            }
        }
    }

    public class PackagedFont {
        public string family;
        public string file;
        public FontLicence licence;
        public bool copied = false;

        public PackagedFont (string family, string file, FontLicence licence) {
            this.family = family;
            this.file = file;
            this.licence = licence;
        }
    }

    public class FontPackager {
        private static uint16 be16 (uint8[] d, int o) {
            if (o < 0 || o + 2 > d.length) return 0;
            return (uint16) (((uint) d[o] << 8) | (uint) d[o + 1]);
        }

        private static uint32 be32 (uint8[] d, int o) {
            if (o < 0 || o + 4 > d.length) return 0;
            return ((uint32) d[o] << 24) | ((uint32) d[o + 1] << 16) | ((uint32) d[o + 2] << 8) | (uint32) d[o + 3];
        }

        public static FontLicence licence_of (uint8[] d) {
            if (d.length < 12) return FontLicence.UNKNOWN;
            int start = 0;
            if (d[0] == 't' && d[1] == 't' && d[2] == 'c' && d[3] == 'f') start = (int) be32 (d, 12);
            int n = be16 (d, start + 4);
            for (int i = 0; i < n && i < 512; i++) {
                int rec = start + 12 + i * 16;
                if (rec + 16 > d.length) break;
                if (d[rec] == 'O' && d[rec + 1] == 'S' && d[rec + 2] == '/' && d[rec + 3] == '2') {
                    int off = (int) be32 (d, rec + 8);
                    if (off + 10 > d.length) return FontLicence.UNKNOWN;
                    uint16 fs = be16 (d, off + 8);
                    if ((fs & 0x0008) != 0) return FontLicence.EDITABLE;
                    if ((fs & 0x0004) != 0) return FontLicence.PRINT_PREVIEW;
                    if ((fs & 0x0002) != 0) return FontLicence.RESTRICTED;
                    return FontLicence.INSTALLABLE;
                }
            }
            return FontLicence.UNKNOWN;
        }

        public static Gee.ArrayList<string> files_for (string family) {
            var list = new Gee.ArrayList<string> ();
            Fc.init ();
            var pat = new Fc.Pattern ();
            pat.add_string ("family", family);
            var os = new Fc.ObjectSet ();
            os.add ("file");
            var set = Fc.font_list (null, pat, os);
            if (set == null) return list;
            for (int i = 0; i < set.nfont; i++) {
                unowned string f;
                if (set.fonts[i].get_string ("file", 0, out f) == Fc.Result.Match && f != null && !list.contains (f)) list.add (f);
            }
            list.sort ();
            return list;
        }

        public static Gee.ArrayList<PackagedFont> collect (Gee.List<string> families, string dest_dir) {
            var result = new Gee.ArrayList<PackagedFont> ();
            DirUtils.create_with_parents (dest_dir, 0755);
            foreach (string fam in families) {
                foreach (string file in files_for (fam)) {
                    uint8[] data;
                    try {
                        FileUtils.get_data (file, out data);
                    } catch (Error e) {
                        continue;
                    }
                    var pf = new PackagedFont (fam, file, licence_of (data));
                    if (pf.licence.may_copy ()) {
                        try {
                            FileUtils.set_data (Path.build_filename (dest_dir, Path.get_basename (file)), data);
                            pf.copied = true;
                        } catch (Error e) {
                            pf.copied = false;
                        }
                    }
                    result.add (pf);
                }
            }
            return result;
        }
    }
}
