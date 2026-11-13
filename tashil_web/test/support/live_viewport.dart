/// Live logical size derived from the v141 production screenshots.
///
/// Captures are 1920×1200 device pixels of Chrome full-screen at 150% zoom,
/// so the logical viewport is 1280×800. The desktop sidebar is 250dp
/// (`desktop_sidebar.dart`), which leaves [kLiveContentWidth] for the page.
/// Widget tests that pump a screen without the shell must use that content
/// width — pumping at 1280 overstates the space the table and chips get.
const double kLiveViewportWidth = 1280.0;
const double kLiveViewportHeight = 800.0;
const double kLiveSidebarWidth = 250.0;
const double kLiveContentWidth = kLiveViewportWidth - kLiveSidebarWidth; // 1030
