# Package

version       = "0.1.0"
author        = "MegaIng"
description   = "An extractor for TC's .sol/.hs files"
license       = "CC0-1.0"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["tc_hs_extractor"]


# Dependencies

requires "nim >= 1.4.0", "argparse"
