//
//  VELEventHandlingTests.m
//  Velvet
//
//  Created by Justin Spahr-Summers on 22.03.12.
//  Copyright (c) 2012 Bitswift. All rights reserved.
//

#import <Velvet/Velvet.h>
#import <Velvet/VELEventRecognizerProtected.h>

// returns an NSUInteger mask combining the given mouse button numbers
#define BUTTON_MASK_FOR_BUTTONS(...) \
    ^{ \
        NSUInteger buttons[] = { __VA_ARGS__ }; \
        NSUInteger mask = 0; \
        \
        for (NSUInteger i = 0; i < sizeof(buttons) / sizeof(*buttons); ++i) { \
            NSUInteger button = buttons[i]; \
            \
            mask |= (1 << button); \
        } \
        \
        return mask; \
    }()

// the starting eventNumber for "true" mouse events (created in our tests)
//
// NSSystemDefined events (also created in our tests) will have an event number
// below this
static const NSInteger trueMouseEventNumberMinimum = 1000;

@interface DeduplicationTestRecognizer : VELEventRecognizer
/**
 * A mask for events that this recognizer should accept.
 *
 * Once the recognizer receives an event matching this mask, that bit in the
 * mask is cleared (such that another event of the same type will fail).
 */
@property (nonatomic, assign) NSUInteger expectedEventMask;
@end

@interface NSEvent (SystemDefinedEventCreation)
+ (NSEvent *)systemDefinedMouseEventAtLocation:(CGPoint)location mouseButtonStateMask:(NSUInteger)buttonStateMask mouseButtonStateChangedMask:(NSUInteger)buttonStateChangedMask;

+ (void)stopEventLoop;
@end

SpecBegin(VELEventHandling)

    describe(@"converting system-defined events to real mouse events", ^{
        __block CGPoint location;

        // to be set by the 'it' blocks below
        __block NSEvent *systemEvent;
        __block NSUInteger buttonMask;
        __block NSUInteger changeMask;

        before(^{
            systemEvent = nil;
            buttonMask = 0;
            changeMask = 0;

            location = CGPointMake(320, 480);
        });

        after(^{
            // verify some invariants about the system event
            expect(systemEvent).not.toBeNil();
            expect(systemEvent.hasMouseButtonState).toBeTruthy();
            expect(systemEvent.mouseButtonStateMask).toEqual(buttonMask);
            expect(systemEvent.mouseButtonStateChangedMask).toEqual(changeMask);
            expect(systemEvent.window).toBeNil();

            // and the corresponding mouse events
            NSArray *mouseEvents = systemEvent.correspondingMouseEvents;
            expect(mouseEvents.count).toBeGreaterThan(0);

            for (NSEvent *event in mouseEvents) {
                expect(fabs(event.timestamp - systemEvent.timestamp)).toBeLessThan(0.0001);
                expect(event.window).toBeNil();

                expect(event.locationInWindow).toEqual(systemEvent.locationInWindow);
            }
        });

        it(@"should convert a left mouse down event", ^{
            buttonMask = BUTTON_MASK_FOR_BUTTONS(0);
            changeMask = BUTTON_MASK_FOR_BUTTONS(0);

            systemEvent = [NSEvent
                systemDefinedMouseEventAtLocation:location
                mouseButtonStateMask:buttonMask
                mouseButtonStateChangedMask:changeMask
            ];

            NSArray *mouseEvents = systemEvent.correspondingMouseEvents;
            expect(mouseEvents.count).toEqual(1);

            NSEvent *event = mouseEvents.lastObject;
            expect(event.type).toEqual(NSLeftMouseDown);
        });

        it(@"should convert a left mouse up event", ^{
            buttonMask = 0;
            changeMask = BUTTON_MASK_FOR_BUTTONS(0);

            systemEvent = [NSEvent
                systemDefinedMouseEventAtLocation:location
                mouseButtonStateMask:buttonMask
                mouseButtonStateChangedMask:changeMask
            ];

            NSArray *mouseEvents = systemEvent.correspondingMouseEvents;
            expect(mouseEvents.count).toEqual(1);

            NSEvent *event = mouseEvents.lastObject;
            expect(event.type).toEqual(NSLeftMouseUp);
        });

        it(@"should convert a left mouse down + right mouse up event", ^{
            buttonMask = BUTTON_MASK_FOR_BUTTONS(0);
            changeMask = BUTTON_MASK_FOR_BUTTONS(0, 1);

            systemEvent = [NSEvent
                systemDefinedMouseEventAtLocation:location
                mouseButtonStateMask:buttonMask
                mouseButtonStateChangedMask:changeMask
            ];

            NSArray *mouseEvents = systemEvent.correspondingMouseEvents;
            expect(mouseEvents.count).toEqual(2);

            NSEvent *leftEvent = [mouseEvents objectAtIndex:0];
            expect(leftEvent.type).toEqual(NSLeftMouseDown);

            NSEvent *rightEvent = [mouseEvents objectAtIndex:1];
            expect(rightEvent.type).toEqual(NSRightMouseUp);
        });

        it(@"should convert mouse down event for other mouse buttons 2 - 4", ^{
            buttonMask = BUTTON_MASK_FOR_BUTTONS(2, 3, 4);
            changeMask = BUTTON_MASK_FOR_BUTTONS(2, 3, 4);

            systemEvent = [NSEvent
                systemDefinedMouseEventAtLocation:location
                mouseButtonStateMask:buttonMask
                mouseButtonStateChangedMask:changeMask
            ];

            NSArray *mouseEvents = systemEvent.correspondingMouseEvents;
            expect(mouseEvents.count).toEqual(3);

            NSUInteger button = 2;
            for (NSEvent *event in mouseEvents) {
                expect(event.type).toEqual(NSOtherMouseDown);
                expect(event.buttonNumber).toEqual(button);

                ++button;
            }
        });
    });

    describe(@"deduplicating system-defined events", ^{
        __block VELWindow *window;
        __block DeduplicationTestRecognizer *recognizer;

        __block NSEvent *leftMouseDownEvent;
        __block NSEvent *rightMouseUpEvent;
        __block NSEvent *systemDefinedEvent;

        before(^{
            window = [[VELWindow alloc] initWithContentRect:NSMakeRect(112, 237, 500, 1000)];
            expect(window).not.toBeNil();

            [window makeKeyAndOrderFront:nil];

            recognizer = [[DeduplicationTestRecognizer alloc] init];
            expect(recognizer).not.toBeNil();

            recognizer.view = window.rootView;

            __block NSInteger eventNumber = trueMouseEventNumberMinimum;

            NSEvent *(^mouseEventAtWindowLocation)(NSEventType, CGPoint) = ^(NSEventType type, CGPoint point){
                return [NSEvent
                    mouseEventWithType:type
                    location:point
                    modifierFlags:0
                    timestamp:[[NSProcessInfo processInfo] systemUptime]
                    windowNumber:window.windowNumber
                    context:window.graphicsContext
                    eventNumber:eventNumber++
                    clickCount:1
                    pressure:1
                ];
            };

            CGPoint location = CGPointMake(215, 657);

            leftMouseDownEvent = mouseEventAtWindowLocation(NSLeftMouseDown, location);
            rightMouseUpEvent = mouseEventAtWindowLocation(NSRightMouseUp, location);

            systemDefinedEvent = [NSEvent
                systemDefinedMouseEventAtLocation:location
                mouseButtonStateMask:BUTTON_MASK_FOR_BUTTONS(0)
                mouseButtonStateChangedMask:BUTTON_MASK_FOR_BUTTONS(0, 1)
            ];

            recognizer.expectedEventMask = NSLeftMouseDownMask | NSRightMouseUpMask;
        });

        after(^{
            [NSEvent performSelector:@selector(stopEventLoop) withObject:nil afterDelay:0.1];
            [[NSApplication sharedApplication] run];

            // the recognizer should not be expecting any further events
            expect(recognizer.expectedEventMask).toEqual(0);

            recognizer = nil;
        });

        it(@"should deduplicate an NSSystemDefined event arriving after mouse events", ^{
            [NSApp postEvent:leftMouseDownEvent atStart:NO];
            [NSApp postEvent:rightMouseUpEvent atStart:NO];
            [NSApp postEvent:systemDefinedEvent atStart:NO];
        });

        it(@"should deduplicate an NSSystemDefined event queued before mouse events", ^{
            [NSApp postEvent:systemDefinedEvent atStart:NO];
            [NSApp postEvent:leftMouseDownEvent atStart:NO];
            [NSApp postEvent:rightMouseUpEvent atStart:NO];
        });

        it(@"should deduplicate an NSSystemDefined event arriving in-between mouse events", ^{
            [NSApp postEvent:leftMouseDownEvent atStart:NO];
            [NSApp postEvent:systemDefinedEvent atStart:NO];
            [NSApp postEvent:rightMouseUpEvent atStart:NO];
        });
    });

SpecEnd

@implementation NSEvent (SystemDefinedEventCreation)
+ (NSEvent *)systemDefinedMouseEventAtLocation:(CGPoint)location mouseButtonStateMask:(NSUInteger)buttonStateMask mouseButtonStateChangedMask:(NSUInteger)buttonStateChangedMask; {
    return [NSEvent
        otherEventWithType:NSSystemDefined
        location:location
        modifierFlags:0
        timestamp:[[NSProcessInfo processInfo] systemUptime]
        windowNumber:0
        context:nil
        subtype:7 // special mouse event subtype
        data1:(NSInteger)buttonStateChangedMask
        data2:(NSInteger)buttonStateMask
    ];
}

+ (void)stopEventLoop; {
    [NSApp stop:nil];

    NSEvent *event = [NSEvent otherEventWithType: NSApplicationDefined
        location:CGPointZero
        modifierFlags:0
        timestamp:0.0
        windowNumber:0
        context:nil
        subtype:0
        data1:0
        data2:0
    ];
    
    [NSApp postEvent:event atStart:YES];
}
@end

@implementation DeduplicationTestRecognizer
@synthesize expectedEventMask = m_expectedEventMask;

- (BOOL)handleEvent:(NSEvent *)event {
    @try {
        // this should not be a converted NSSystemDefined event
        expect(event.eventNumber).toBeGreaterThanOrEqualTo(trueMouseEventNumberMinimum);

        NSUInteger eventMask = NSEventMaskFromType(event.type);
        expect(self.expectedEventMask & eventMask).toEqual(eventMask);

        [super handleEvent:event];

        // remove this event's mask
        self.expectedEventMask &= (~eventMask);
    } @catch (NSException *ex) {
        // manually abort from exceptions, since AppKit likes to catch them
        NSLog(@"Exception thrown: %@", ex);
        abort();
    }

    // don't consume or actually "accept" any events -- we just want to test
    // event deduplication
    return NO;
}

@end
