@@
-import SwiftUI
-import UIKit
-
-struct SystemInfoView: View {
+import SwiftUI
+import UIKit
+import Security
+
+struct SystemInfoView: View {
@@
-// Helper function to check entitlements using SecTask API
-private func checkEntitlement(_ entitlement: String) -\u003e Bool {
-    // Use SecTaskCreateFromSelf to check our own entitlements
-    guard let task = SecTaskCreateFromSelf(nil) else {
-        return false
-    }
-    
-    // Query the specific entitlement
-    guard let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) else {
-        return false
-    }
-    
-    // Check if it's a boolean true value
-    if CFGetTypeID(value) == CFBooleanGetTypeID() {
-        return CFBooleanGetValue(value as! CFBoolean)
-    }
-    
-    // Some entitlements might be strings or arrays (just check presence)
-    return true
-}
+// Helper function to check entitlements using SecTask API
+private func checkEntitlement(_ entitlement: String) -> Bool {
+    // Use SecTaskCreateFromSelf to check our own entitlements
+    guard let task = SecTaskCreateFromSelf(nil) else {
+        return false
+    }
+
+    var error: Unmanaged<CFError>?
+    guard let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, &error) else {
+        return false
+    }
+
+    // Check if it's a boolean true value
+    if CFGetTypeID(value) == CFBooleanGetTypeID(), let boolean = value as? CFBoolean {
+        return CFBooleanGetValue(boolean)
+    }
+
+    // If value exists but isn't boolean, treat presence as true
+    return true
+}
@@
-#Preview {
-    NavigationStack {
-        SystemInfoView()
-    }
-}
+struct SystemInfoView_Previews: PreviewProvider {
+    static var previews: some View {
+        NavigationStack { SystemInfoView() }
+    }
+}
