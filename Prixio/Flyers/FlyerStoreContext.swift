import Foundation

/// A default geographic/store context injected into a flyer page so its
/// store-selection gate releases prices. Most Alberta grocery SPAs won't render
/// flyer items until a store or postal code is chosen; supplying one (via
/// geolocation override, postal-code seeding, and the store picker) is what gets
/// past the gate.
struct FlyerStoreContext: Equatable {
    let provinceCode: String
    let city: String
    /// Postal code without a space, e.g. `T2P1J9`.
    let postalCode: String
    /// Postal code with the conventional space, e.g. `T2P 1J9`.
    let postalCodeSpaced: String
    let latitude: Double
    let longitude: Double

    var label: String { "\(provinceCode)/\(city)/\(postalCode)" }

    /// Downtown Calgary — a dense Alberta location every supported banner serves.
    static let defaultAlberta = FlyerStoreContext(
        provinceCode: "AB",
        city: "Calgary",
        postalCode: "T2P1J9",
        postalCodeSpaced: "T2P 1J9",
        latitude: 51.0447,
        longitude: -114.0719
    )
}

/// Per-banner instructions for getting past a store-selection gate, layered on top
/// of the universal levers in `FlyerStoreInjection`. Currently most banners rely on
/// the universal levers; this struct is the hook where device-verified per-banner
/// cookies/keys get added without touching the acquirer.
struct FlyerStorePreparation: Equatable {
    /// Cookies to seed on the discovered host before load (name → value).
    var cookies: [String: String] = [:]
    /// Extra JavaScript appended to the universal document-start script (e.g.
    /// banner-specific localStorage keys).
    var documentStartScript: String? = nil
    /// Whether this banner is known to embed its flyer in a cross-origin iframe
    /// (Flipp). `innerText` cannot read those, so a `true` here tells the acquirer
    /// to flag the result for the snapshot/OCR or endpoint path rather than calling
    /// an empty read a "no prices" gate failure.
    var flyerInCrossOriginIframe: Bool = false
    /// Whether this banner is known to sit behind an anti-bot wall (Akamai) that a
    /// store context cannot clear. Used to label the result honestly.
    var antiBotWalled: Bool = false
    /// The Flipp **flyerkit** merchant slug, when this banner serves its flyer via
    /// Flipp (`dam.flippenterprise.net/flyerkit/...`). Lets the acquirer fetch items
    /// directly from the flyerkit API as a deterministic fallback when the rendered
    /// widget never fetches products — slugs read from device request diagnostics.
    var flippMerchant: String? = nil
}

enum FlyerStorePreparationCatalog {
    static func preparation(for banner: FlyerBannerID, context: FlyerStoreContext) -> FlyerStorePreparation {
        switch banner {
        case .safeway:
            return FlyerStorePreparation(flyerInCrossOriginIframe: true, flippMerchant: "safeway")
        case .sobeys:
            return FlyerStorePreparation(flyerInCrossOriginIframe: true, flippMerchant: "sobeys")
        case .freshCo:
            return FlyerStorePreparation(flyerInCrossOriginIframe: true, flippMerchant: "freshco")
        case .fresonBros:
            // Flipp family, but its merchant slug isn't confirmed yet (iframe stays
            // about:blank); no flyerkit fallback until a slug is known.
            return FlyerStorePreparation(flyerInCrossOriginIframe: true)
        case .realCanadianSuperstore, .noFrills:
            // Loblaw banners return an Akamai bot-wall shell even through WebKit, and
            // serve items via the pcexpress API (not Flipp).
            return FlyerStorePreparation(antiBotWalled: true)
        case .saveOnFoods:
            // Save-On renders a Salesforce circular, but also exposes a Flipp flyerkit
            // feed; the merchant slug backs the direct-fetch fallback.
            return FlyerStorePreparation(flippMerchant: "saveonfoods")
        case .walmartSupercentre:
            return FlyerStorePreparation(flippMerchant: "walmartcanada")
        case .coOp:
            // food.crs loads only its Flipp merchant config and never selects a
            // publication, so the rendered capture comes up empty — the flyerkit
            // direct fetch (slug "coopfood") is its reliable source.
            return FlyerStorePreparation(flippMerchant: "coopfood")
        case .costco:
            return FlyerStorePreparation()
        }
    }
}

/// Builds the JavaScript injected to defeat store-selection gates. Kept separate and
/// string-pure so the scripts are easy to read, test, and tune from device runs.
enum FlyerStoreInjection {
    /// Runs at document start in every frame (incl. Flipp iframes): overrides
    /// geolocation to the default location and seeds the postal code into the
    /// storage keys grocery SPAs commonly read.
    static func documentStartScript(_ context: FlyerStoreContext, extra: String?) -> String {
        let base = """
        (function(){
          var lat=\(context.latitude), lon=\(context.longitude);
          var pc="\(context.postalCode)", city="\(context.city)", prov="\(context.provinceCode)";
          try {
            var pos={coords:{latitude:lat,longitude:lon,accuracy:40,altitude:null,altitudeAccuracy:null,heading:null,speed:null},timestamp:Date.now()};
            if (navigator.geolocation) {
              navigator.geolocation.getCurrentPosition=function(s){ try{ if(s) s(pos); }catch(e){} };
              navigator.geolocation.watchPosition=function(s){ try{ if(s) s(pos); }catch(e){} return 1; };
            }
          } catch(e){}
          try {
            var keys=["postalCode","postal_code","postalcode","flipp_postal_code","flippPostalCode","userPostalCode","preferredPostalCode","selectedPostalCode","postal"];
            for (var i=0;i<keys.length;i++){ try{ localStorage.setItem(keys[i], pc); }catch(e){} }
            try{ localStorage.setItem("province", prov); }catch(e){}
            try{ localStorage.setItem("city", city); }catch(e){}
          } catch(e){}
          try { window.__prixioStore={postalCode:pc,city:city,province:prov,lat:lat,lon:lon}; } catch(e){}
        })();
        """
        guard let extra, !extra.isEmpty else { return base }
        return base + "\n" + extra
    }

    /// Runs after navigation finishes: fills any postal/location input it can find
    /// and clicks store-confirm / consent buttons. Returns a short status string for
    /// logging. Best-effort and defensive — never throws into the host.
    static func postLoadScript(_ context: FlyerStoreContext) -> String {
        """
        (function(){
          var did=0;
          try {
            var pcs="\(context.postalCodeSpaced)";
            var inputs=document.querySelectorAll('input[type=text],input[type=search],input:not([type])');
            for (var i=0;i<inputs.length;i++){
              var el=inputs[i];
              var hint=((el.name||"")+" "+(el.id||"")+" "+(el.placeholder||"")+" "+(el.getAttribute('aria-label')||"")).toLowerCase();
              if (hint.indexOf('postal')>=0 || hint.indexOf('zip')>=0 || hint.indexOf('location')>=0){
                try {
                  var setter=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
                  setter.call(el, pcs);
                  el.dispatchEvent(new Event('input',{bubbles:true}));
                  el.dispatchEvent(new Event('change',{bubbles:true}));
                  el.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Enter',keyCode:13}));
                  el.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'Enter',keyCode:13}));
                  did++;
                } catch(e){}
              }
            }
            var re=/(set( my)? store|use (my )?location|shop this store|select( a)? store|confirm store|find( a)? store|use this store|accept|i agree|view (the |this )?flyer|see (the |this )?flyer|open (the |this )?flyer|shop (the |this )?flyer|weekly flyer|view all flyers)/i;
            var btns=document.querySelectorAll('button,[role=button],a');
            for (var j=0;j<btns.length && did<10;j++){
              var t=(btns[j].innerText||btns[j].textContent||"").trim();
              if (t && t.length<40 && re.test(t)){ try{ btns[j].click(); did++; }catch(e){} }
            }
          } catch(e){}
          return "did:"+did;
        })();
        """
    }

    /// Scrolls to the bottom to trigger lazy-loaded flyer content; returns the
    /// current visible-text length.
    static let scrollScript = """
    (function(){ try{ window.scrollTo(0, document.body ? document.body.scrollHeight : 0); }catch(e){} return document.body ? document.body.innerText.length : 0; })();
    """

    /// Returns up to a few iframe `src` hosts, so the log shows when flyer content
    /// is isolated in a cross-origin frame (`innerText` can't reach it).
    static let iframeDiagnosticScript = """
    (function(){ try{ return Array.from(document.querySelectorAll('iframe')).map(function(f){return f.src||"";}).filter(Boolean).slice(0,5).join(" | "); }catch(e){ return ""; } })();
    """

    /// Harvests visible text PLUS image `alt`-text, `aria-label`s, and `title`s.
    /// Flyer viewers render prices as images but frequently embed "Product $3.99" in
    /// accessibility attributes that `innerText` ignores — this surfaces those
    /// without OCR. Same-origin only; cross-origin iframes remain unreadable.
    static let textHarvestScript = """
    (function(){
      var out = document.body ? document.body.innerText : "";
      try {
        var nodes = document.querySelectorAll('[alt],[aria-label],[title]');
        var extra = [];
        for (var i=0;i<nodes.length && extra.length<3000;i++){
          var el=nodes[i];
          var a=el.getAttribute('alt')||el.getAttribute('aria-label')||el.getAttribute('title')||"";
          if (a && a.length<200) extra.push(a);
        }
        if (extra.length) out += "\\n" + extra.join("\\n");
      } catch(e){}
      return out;
    })();
    """

    /// Drives a store-locator page programmatically: fills the postal/search field
    /// and submits, then (once results exist) clicks the first store action so the
    /// page navigates to the store-scoped flyer. Idempotent — safe to run each tick:
    /// it fills the postal first, then on later ticks clicks a store result. Returns
    /// a short status string for logging.
    static func storeLocatorScript(_ context: FlyerStoreContext) -> String {
        """
        (function(){
          var pcs = "\(context.postalCodeSpaced)";
          var prefix = pcs.substring(0, 3).toLowerCase();
          function setValue(el, v){
            try {
              var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              setter.call(el, v);
              el.dispatchEvent(new Event('input',{bubbles:true}));
              el.dispatchEvent(new Event('change',{bubbles:true}));
              el.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,key:'Enter',keyCode:13,which:13}));
              el.dispatchEvent(new KeyboardEvent('keyup',{bubbles:true,key:'Enter',keyCode:13,which:13}));
            } catch(e){}
          }
          try {
            var inputs = document.querySelectorAll('input[type=text],input[type=search],input:not([type])');
            var field = null;
            for (var i=0;i<inputs.length;i++){
              var el = inputs[i];
              var hint = ((el.name||"")+" "+(el.id||"")+" "+(el.placeholder||"")+" "+(el.getAttribute('aria-label')||"")).toLowerCase();
              if (hint.indexOf('postal')>=0 || hint.indexOf('zip')>=0 || hint.indexOf('location')>=0 || hint.indexOf('search')>=0 || hint.indexOf('city')>=0){
                field = el; break;
              }
            }
            // Step 1: ensure the postal code is entered.
            if (field && (field.value||"").toLowerCase().indexOf(prefix) < 0){
              setValue(field, pcs);
              return "postal-filled";
            }
            // Step 2: click the first store-selection action.
            var re = /(shop this store|shop now|set( as)?( my)? store|select( store)?|choose( store)?|view (the )?flyer|see (the )?flyer|this store|make my store)/i;
            var actions = document.querySelectorAll('button,a,[role=button]');
            for (var j=0;j<actions.length;j++){
              var t = (actions[j].innerText || actions[j].textContent || "").trim();
              if (t && t.length < 48 && re.test(t)){
                actions[j].click();
                return "clicked:" + t;
              }
            }
          } catch(e){}
          return "waiting";
        })();
        """
    }
}
