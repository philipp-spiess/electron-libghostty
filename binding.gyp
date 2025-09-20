{
    "targets": [
        {
            "target_name": "native_overlay",
            "sources": [
                "src/native_overlay.cc",
                "src/overlay_view.mm",
            ],
            "include_dirs": [
                "<!@(node -p \"require('node-addon-api').include\")",
                "include",
                "third_party/libghostty/include",
                "<(module_root_dir)/native-deps/include",
            ],
            "dependencies": ["<!(node -p \"require('node-addon-api').gyp\")"],
            "defines": ["NODE_ADDON_API_CPP_EXCEPTIONS"],
            "cflags!": ["-fno-exceptions"],
            "cflags_cc!": ["-fno-exceptions"],
            "cflags_cc": ["-std=c++17"],
            "cflags_objcc": ["-fobjc-arc"],
            "xcode_settings": {
                "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
                "CLANG_CXX_LIBRARY": "libc++",
                "MACOSX_DEPLOYMENT_TARGET": "13.0",
                "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
                "CLANG_ENABLE_OBJC_ARC": "YES",
                "OTHER_CFLAGS": [
                    "-fobjc-arc"
                ],
                "OTHER_LDFLAGS": [
                    "-framework AppKit",
                    "-framework Cocoa",
                    "-framework QuartzCore",
                    "-framework Metal",
                    "-framework MetalKit",
                    "-framework CoreGraphics",
                    "-framework CoreText",
                    "-framework CoreVideo",
                    "-framework UniformTypeIdentifiers",
                    "-framework Carbon",
                    "-ObjC"
                ],
            },
            "msvs_settings": {"VCCLCompilerTool": {"ExceptionHandling": 1}},
            "conditions": [
                ["OS=='mac'", {
                    "libraries": [
                        "<(module_root_dir)/native-deps/lib/macos/libghostty.a"
                    ]
                }]
            ],
        }
    ]
}
