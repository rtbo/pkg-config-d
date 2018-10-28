# pkg-config-d

Invoke pkg-config from D code.

```d
import pkg_config;
try {
    auto lib = pkgConfig("freetype2").libs().invoke();
    // use lib.lflags, lib.libs, lib.libPaths
}
catch (Exception ex)
{
    // pkg-config not installed or freetype not present
}
```