;; test_base64.nu
;;  tests for Nunja base64 encoding and decoding
;; Created by Patrick Thomson on 2008-08-26.

(load "Nunja")

(class TestBase64 is NuTestCase
     
     (- testEncoding is
        (set toEncode "business time")
        (set encoded (toEncode stringByEncodingWithBase64))
        ;; Obtained from the command line
        (assert_equal encoded "YnVzaW5lc3MgdGltZQ==")
        (assert_equal (encoded stringByDecodingFromBase64) toEncode)))

