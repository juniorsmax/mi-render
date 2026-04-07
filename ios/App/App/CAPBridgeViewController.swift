import UIKit
import Capacitor
import WebKit

/**
 * CAPBridgeViewController — configuración del WKWebView para mi-render
 * Agente: Kai (iOS)
 *
 * Problema: WKWebView bloquea getUserMedia por defecto aunque
 * NSCameraUsageDescription esté en Info.plist.
 * Solución: implementar el delegate de permisos de media capture.
 */
class CAPBridgeViewController: CAPBridgeViewController {

    override func webView(_ webView: WKWebView,
                          requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                          initiatedByFrame frame: WKFrameInfo,
                          type: WKMediaCaptureType,
                          decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Conceder permiso de cámara automáticamente al WKWebView
        // El sistema iOS ya habrá pedido el permiso al usuario via NSCameraUsageDescription
        decisionHandler(.grant)
    }

    override func webView(_ webView: WKWebView,
                          requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                          initiatedByFrame frame: WKFrameInfo,
                          decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}
