#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Registro del plugin LiDAR para que Capacitor lo encuentre
CAP_PLUGIN(LiDARPlugin, "LiDARPlugin",
    CAP_PLUGIN_METHOD(isAvailable, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startScan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startObjectScan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startPhotogrammetry, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startWalkthrough, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(stopScan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportUSDZ, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(saveWorldMap, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(measureDistance, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportOBJ, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportPLY, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportSTL, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportDXF, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportDAE, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportSVG, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportPDF, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportGLTF, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportGLB, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportAllFormats, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getSurfaceAreas, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getWallMetrics, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getFloorFootprint, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(renderFloorPlan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getRoomSegmentation, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(getAutoVolume, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportIFC, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(exportOptimizedUSDZ, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(listProjects, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openViewer, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(deleteProject, CAPPluginReturnPromise);
)
