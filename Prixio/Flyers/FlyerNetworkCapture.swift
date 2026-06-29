import Foundation
import WebKit

/// Captures the flyer-data network calls a page (or its cross-origin Flipp/Salesforce
/// iframe) makes client-side, by hooking `fetch`/`XMLHttpRequest` from an injected
/// document-start script and posting flyer-looking response bodies back to native.
///
/// This is the most reliable price source for banners the renderer/OCR can't read:
/// the structured JSON the SPA itself fetches contains product names, prices, and
/// dates — no rendering, no image decode, no store-selection gate. Because the
/// interceptor is installed in **all frames** (WKUserScript ignores the same-origin
/// policy for injection), it also captures the Flipp iframe's own flyer fetch that
/// `innerText` and even a content PDF cannot reach.
@MainActor
final class FlyerNetworkCapture: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "prixioFlyer"

    private(set) var payloads: [String] = []
    private var totalBytes = 0
    private let maxBytes = 800_000

    var payloadCount: Int { payloads.count }
    var capturedText: String { payloads.joined(separator: "\n") }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let dict = message.body as? [String: Any],
              let body = dict["body"] as? String,
              !body.isEmpty,
              totalBytes < maxBytes else {
            return
        }
        payloads.append(body)
        totalBytes += body.utf8.count
    }

    /// Counts flyer price signals across both `$X.XX` text and JSON `"price": 3.99`
    /// (or `current_price`) forms, since captured payloads are usually structured.
    static func priceSignalCount(in text: String) -> Int {
        let lower = text.lowercased()
        let dollar = FlyerSourceShapeClassifier.priceTokenCount(in: lower)
        let json = regexMatchCount(
            "\"(current_|sale_|reg_)?price\"\\s*:\\s*\"?\\$?\\d{1,4}(\\.\\d{1,2})?",
            in: lower
        )
        return dollar + json
    }

    private static func regexMatchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Installed at document start in every frame. Hooks `fetch` and `XMLHttpRequest`
    /// and posts back response bodies whose URL/content look like flyer data.
    static let interceptorScript = """
    (function(){
      if (window.__prixioHooked) { return; }
      window.__prixioHooked = true;
      function looksFlyer(u, body){
        var s = ((u||"") + " " + (body||"").substring(0,300)).toLowerCase();
        return s.indexOf('flipp')>=0 || s.indexOf('flyer')>=0 || s.indexOf('circular')>=0
            || s.indexOf('publication')>=0 || s.indexOf('current_price')>=0
            || s.indexOf('"price"')>=0 || s.indexOf('/items')>=0 || s.indexOf('product')>=0
            || s.indexOf('wishabi')>=0 || s.indexOf('backflipp')>=0;
      }
      function post(u, body){
        try {
          if (!body || body.length < 40) { return; }
          if (!looksFlyer(u, body)) { return; }
          window.webkit.messageHandlers.\(messageHandlerName).postMessage({ url: ""+u, body: body.substring(0, 250000) });
        } catch(e){}
      }
      try {
        var origFetch = window.fetch;
        if (origFetch) {
          window.fetch = function(){
            var a0 = arguments[0];
            var url = (a0 && a0.url) ? a0.url : a0;
            return origFetch.apply(this, arguments).then(function(resp){
              try { resp.clone().text().then(function(t){ post(""+url, t); }).catch(function(){}); } catch(e){}
              return resp;
            });
          };
        }
      } catch(e){}
      try {
        var oOpen = XMLHttpRequest.prototype.open;
        var oSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(m, u){ this.__prixioURL = u; return oOpen.apply(this, arguments); };
        XMLHttpRequest.prototype.send = function(){
          var xhr = this;
          try {
            xhr.addEventListener('load', function(){ try { post(""+xhr.__prixioURL, xhr.responseText); } catch(e){} });
          } catch(e){}
          return oSend.apply(this, arguments);
        };
      } catch(e){}
    })();
    """
}
