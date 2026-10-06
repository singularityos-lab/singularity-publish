[CCode (cheader_filename = "lcms2.h", lower_case_cprefix = "cms", cprefix = "cms")]
namespace Lcms {
    [CCode (cname = "TYPE_RGB_8")]
    public const uint32 TYPE_RGB_8;
    [CCode (cname = "TYPE_CMYK_8")]
    public const uint32 TYPE_CMYK_8;
    [CCode (cname = "TYPE_RGB_DBL")]
    public const uint32 TYPE_RGB_DBL;
    [CCode (cname = "TYPE_CMYK_DBL")]
    public const uint32 TYPE_CMYK_DBL;
    [CCode (cname = "cmsFLAGS_BLACKPOINTCOMPENSATION")]
    public const uint32 FLAGS_BLACKPOINTCOMPENSATION;
    [CCode (cname = "cmsFLAGS_NOCACHE")]
    public const uint32 FLAGS_NOCACHE;
    [CCode (cname = "cmsSigCmykData")]
    public const uint32 SIG_CMYK_DATA;
    [CCode (cname = "cmsSigRgbData")]
    public const uint32 SIG_RGB_DATA;
    [CCode (cname = "cmsSigLabData")]
    public const uint32 SIG_LAB_DATA;
    [CCode (cname = "cmsSigOutputClass")]
    public const uint32 SIG_OUTPUT_CLASS;
    [CCode (cname = "cmsSigAToB0Tag")]
    public const uint32 SIG_ATOB0;
    [CCode (cname = "cmsSigAToB1Tag")]
    public const uint32 SIG_ATOB1;
    [CCode (cname = "cmsSigAToB2Tag")]
    public const uint32 SIG_ATOB2;
    [CCode (cname = "cmsSigBToA0Tag")]
    public const uint32 SIG_BTOA0;
    [CCode (cname = "cmsSigBToA1Tag")]
    public const uint32 SIG_BTOA1;
    [CCode (cname = "cmsSigBToA2Tag")]
    public const uint32 SIG_BTOA2;
    [CCode (cname = "cmsSigProfileDescriptionTag")]
    public const uint32 SIG_DESCRIPTION;
    [CCode (cname = "cmsSigCopyrightTag")]
    public const uint32 SIG_COPYRIGHT;
    [CCode (cname = "cmsSigMediaWhitePointTag")]
    public const uint32 SIG_MEDIA_WHITE_POINT;
    [CCode (cname = "cmsInfoDescription")]
    public const int INFO_DESCRIPTION;
    [CCode (cname = "cmsAT_END")]
    public const int AT_END;

    [CCode (cname = "cmsSAMPLER16", has_target = false)]
    public delegate int Sampler16 ([CCode (array_length = false)] uint16[] input, [CCode (array_length = false)] uint16[] output, void* cargo);

    [Compact]
    [CCode (cname = "void", free_function = "cmsCloseProfile")]
    public class Profile {
        [CCode (cname = "cmsOpenProfileFromMem")]
        public static Profile? from_mem ([CCode (array_length_type = "guint32")] uint8[] data);
        [CCode (cname = "cmsOpenProfileFromFile")]
        public static Profile? from_file (string path, string access = "r");
        [CCode (cname = "cmsCreate_sRGBProfile")]
        public static Profile srgb ();
        [CCode (cname = "cmsCreateProfilePlaceholder")]
        public static Profile placeholder (void* context = null);
        [CCode (cname = "cmsGetColorSpace")]
        public uint32 color_space ();
        [CCode (cname = "cmsGetDeviceClass")]
        public uint32 device_class ();
        [CCode (cname = "cmsGetProfileInfoASCII")]
        public uint32 info_ascii (int info, string lang, string country, [CCode (array_length = false)] char[]? buffer, uint32 size);
        [CCode (cname = "cmsSaveProfileToMem")]
        public bool save_to_mem (void* mem, ref uint32 needed);
        [CCode (cname = "cmsSetProfileVersion")]
        public void set_version (double v);
        [CCode (cname = "cmsSetDeviceClass")]
        public void set_device_class (uint32 sig);
        [CCode (cname = "cmsSetColorSpace")]
        public void set_color_space (uint32 sig);
        [CCode (cname = "cmsSetPCS")]
        public void set_pcs (uint32 sig);
        [CCode (cname = "cmsSetHeaderRenderingIntent")]
        public void set_rendering_intent (uint32 intent);
        [CCode (cname = "cmsWriteTag")]
        public bool write_tag (uint32 sig, void* data);
    }

    [Compact]
    [CCode (cname = "void", free_function = "cmsDeleteTransform")]
    public class Transform {
        [CCode (cname = "cmsCreateTransform")]
        public static Transform? create (Profile input, uint32 in_format, Profile output, uint32 out_format, uint32 intent, uint32 flags);
        [CCode (cname = "cmsDoTransform")]
        public void apply (void* input, void* output, uint32 size);
    }

    [Compact]
    [CCode (cname = "cmsStage", free_function = "cmsStageFree")]
    public class Stage {
        [CCode (cname = "cmsStageAllocCLut16bit")]
        public static Stage? clut16 (void* context, uint32 grid, uint32 in_channels, uint32 out_channels, uint16* table = null);
        [CCode (cname = "cmsStageSampleCLut16bit")]
        public bool sample16 (Sampler16 sampler, void* cargo, uint32 flags);
    }

    [Compact]
    [CCode (cname = "cmsPipeline", free_function = "cmsPipelineFree")]
    public class Pipeline {
        [CCode (cname = "cmsPipelineAlloc")]
        public Pipeline (void* context, uint32 in_channels, uint32 out_channels);
        [CCode (cname = "cmsPipelineInsertStage")]
        public bool insert_stage (int loc, owned Stage stage);
    }

    [Compact]
    [CCode (cname = "cmsMLU", free_function = "cmsMLUfree")]
    public class MLU {
        [CCode (cname = "cmsMLUalloc")]
        public MLU (void* context, uint32 items);
        [CCode (cname = "cmsMLUsetASCII")]
        public bool set_ascii (string lang, string country, string text);
    }

    [CCode (cname = "(void*) cmsD50_XYZ")]
    public void* d50_xyz ();
}
