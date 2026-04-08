#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Registro del plugin LiDAR para que Capacitor lo encuentre
CAP_PLUGIN(LiDARPlugin, "LiDARPlugin",
    CAP_PLUGIN_METHOD(isAvailable, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startScan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(startObjectScan, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(stopScan, CAPPluginReturnPromise);
)
