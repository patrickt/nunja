/*!
    @file helpers.m
    @copyright Copyright (c) 2007 Tim Burks, Neon Design Technology, Inc.
    @discussion General utilities for Nunja.
*/

#import "helpers.h"
#import <arpa/inet.h>

static unichar char_to_int(unichar c)
{
    switch (c) {
        case '0': return 0;
        case '1': return 1;
        case '2': return 2;
        case '3': return 3;
        case '4': return 4;
        case '5': return 5;
        case '6': return 6;
        case '7': return 7;
        case '8': return 8;
        case '9': return 9;
        case 'A': case 'a': return 10;
        case 'B': case 'b': return 11;
        case 'C': case 'c': return 12;
        case 'D': case 'd': return 13;
        case 'E': case 'e': return 14;
        case 'F': case 'f': return 15;
    }
    return 0;                                     // not good
}

static char int_to_char[] = "0123456789ABCDEF";

@implementation NSString(NuHTTP)

- (NSString *) urlEncode
{
    NSMutableString *result = [NSMutableString string];
    int i = 0;
    int max = [self length];
    while (i < max) {
        unichar c = [self characterAtIndex:i++];
        if (iswalpha(c) || iswdigit(c) || (c == '-') || (c == '.') || (c == '_') || (c == '~'))
            [result appendFormat:@"%C", c];
        else
            [result appendString:[NSString stringWithFormat:@"%%%c%c", int_to_char[(c/16)%16], int_to_char[c%16]]];
    }
    return result;
}

- (NSString *) urlDecode
{
    NSMutableString *result = [NSMutableString string];
    int i = 0;
    int max = [self length];
    while (i < max) {
        unichar c = [self characterAtIndex:i++];
        switch (c) {
            case '+':
                [result appendString:@" "];
                break;
            case '%':
                [result appendFormat:@"%C",
                    char_to_int([self characterAtIndex:i++])*16
                    + char_to_int([self characterAtIndex:i++])];
                break;
            default:
                [result appendFormat:@"%C", c];
        }
    }
    return result;
}

- (NSDictionary *) urlQueryDictionary
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *pairs = [self componentsSeparatedByString:@"&"];
    int i;
    int max = [pairs count];
    for (i = 0; i < max; i++) {
        NSArray *pair = [[pairs objectAtIndex:i] componentsSeparatedByString:@"="];
        if ([pair count] == 2) {
            NSString *key = [pair objectAtIndex:0];
            NSString *value = [[pair objectAtIndex:1] urlDecode];
            [result setValue:value forKey:key];
        }
    }
    return result;
}

@end

@implementation NSDictionary (NuHTTP)
- (NSString *) urlQueryString
{
    NSMutableString *result = [NSMutableString string];
    NSEnumerator *keyEnumerator = [[self allKeys] objectEnumerator];
    id key;
    while (key = [keyEnumerator nextObject]) {
        if ([result length] > 0) [result appendString:@"&"];
        [result appendString:[NSString stringWithFormat:@"%@=%@", [key urlEncode], [[self objectForKey:key] urlEncode]]];
    }
    return [NSString stringWithString:result];
}

@end

static NSMutableDictionary *parseHeaders(const char *headers)
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    int max = strlen(headers);
    int start = 0;
    int cursor = 0;
    while (cursor < max) {
        while ((headers[cursor] != ':') && (headers[cursor] != '=')) {
            cursor++;
        }
        NSString *key = [[[NSString alloc] initWithBytes:(headers+start)
            length:(cursor - start) encoding:NSASCIIStringEncoding] autorelease];
        //NSLog(@"got key[%@]", key);
        cursor++;

        // skip whitespace
        while (headers[cursor] == ' ') {cursor++;}
        start = cursor;
        while (headers[cursor] && (headers[cursor] != ';') && ((headers[cursor] != 13) || (headers[cursor+1] != 10))) {
            cursor++;
        }

        NSString *value;
                                                  // strip quotes
        if ((headers[start] == '"') && (headers[cursor-1] == '"'))
            value = [[[NSString alloc] initWithBytes:(headers+start+1) length:(cursor-start-2) encoding:NSASCIIStringEncoding] autorelease];
        else
            value = [[[NSString alloc] initWithBytes:(headers+start) length:(cursor-start) encoding:NSASCIIStringEncoding] autorelease];
        //NSLog(@"got value[%@]", value);
        [dict setObject:value forKey:key];

        if (headers[cursor] == ';')
            cursor++;
        else cursor += 2;
        // skip whitespace
        while (headers[cursor] == ' ') {cursor++;}
        start = cursor;
    }

    return dict;
}

@implementation NSData (NuHTTP)
- (NSDictionary *) urlQueryDictionary
{
    NSString *string = [[[NSString alloc] initWithData:self encoding:NSUTF8StringEncoding] autorelease];
    return [string urlQueryDictionary];
}

- (NSDictionary *) multipartDictionaryWithBoundary:(NSString *) boundary
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    const char *bytes = (const char *) [self bytes];
    const char *pattern = [boundary cStringUsingEncoding:NSUTF8StringEncoding];

    //NSLog(@"pattern: %s", pattern);

    // scan through bytes, looking for pattern.
    // split on pattern.
    int cursor = 0;
    int start = 0;
    int max = [self length];
    //NSLog(@"max = %d", max);
    while (cursor < max) {
        if (bytes[cursor] == pattern[0]) {
            // try to scan pattern
            int i;
            int patternLength = strlen(pattern);
            BOOL match = YES;
            for (i = 0; i < patternLength; i++) {
                if (bytes[cursor+i] != pattern[i]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                if (start != 0) {
                                                  // skip first cr/lf
                    int startOfHeaders = start + 2;
                    // scan forward to end of headers
                    int cursor2 = startOfHeaders;
                    while ((bytes[cursor2] != (char) 0x0d) ||
                        (bytes[cursor2+1] != (char) 0x0a) ||
                        (bytes[cursor2+2] != (char) 0x0d) ||
                        (bytes[cursor2+3] != (char) 0x0a)) cursor2++;
                    int lengthOfHeaders = cursor2 - startOfHeaders;
                    char *headers = (char *) malloc((lengthOfHeaders + 1) * sizeof(char));
                    strncpy(headers, bytes+startOfHeaders, lengthOfHeaders);
                    headers[lengthOfHeaders] = 0;

                    // Process headers.
                    NSMutableDictionary *item = parseHeaders(headers);

                    int startOfData = cursor2 + 4;// skip CR/LF pair
                                                  // skip CR/LF and final two hyphens
                    int lengthOfData = cursor - startOfData - 4;

                    if (([item valueForKey:@"Content-Type"] == nil) && ([item valueForKey:@"filename"] == nil)) {
                        NSString *string = [[[NSString alloc] initWithBytes:(bytes+startOfData) length:lengthOfData encoding:NSUTF8StringEncoding] autorelease];
                        [dict setObject:string forKey:[item valueForKey:@"name"]];
                    }
                    else {
                        NSData *data = [NSData dataWithBytes:(bytes+startOfData) length:lengthOfData];
                        [item setObject:data forKey:@"data"];
                        [dict setObject:item forKey:[item valueForKey:@"name"]];
                    }
                }
                cursor = cursor + patternLength - 1;
                start = cursor + 1;
            }
        }
        cursor++;
    }

    return dict;
}

@end
