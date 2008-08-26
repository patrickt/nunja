;; test_base64.nu
;;  tests for Nunja base64 encoding and decoding
;; Created by Patrick Thomson on 2008-08-26.

(load "Nunja")

(class TestBase64 is NuTestCase
     
     (- testEncoding is
        (set toEncode "business time")
        (set encoded (toEncode base64Data))
        ;; Obtained from the command line
        (assert_equal ((NSString alloc) initWithData:encoded encoding:NSUTF8StringEncoding) "YnVzaW5lc3MgdGltZQ==")))

