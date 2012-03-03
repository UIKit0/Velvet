//
//  VELEventRecognizerTests.m
//  Velvet
//
//  Created by Justin Spahr-Summers on 02.03.12.
//  Copyright (c) 2012 Bitswift. All rights reserved.
//

#import <Velvet/Velvet.h>
#import <Velvet/VELEventRecognizerProtected.h>

@interface TestEventRecognizer : VELEventRecognizer
/**
 * The `NSEvent` objects that need to be recognized in sequence.
 */
@property (nonatomic, copy) NSArray *eventsToRecognize;

/**
 * If not `nil`, this recognizer will be continuous, and will continue to
 * generate actions for as long as this event is sent. Otherwise, this
 * recognizer will be discrete.
 */
@property (nonatomic, copy) NSEvent *continuousEvent;

/**
 * Whether <[VELEventRecognizer willTransitionToState:]> was invoked, and the
 * receiver has not yet received a matching <[VELEventRecognizer
 * didTransitionFromState:]> call.
 */
@property (nonatomic, assign) BOOL willTransitionInvoked;

/**
 * Whether <[VELEventRecognizer reset]> was invoked.
 */
@property (nonatomic, assign) BOOL didReset;

/**
 * Transitions the receiver to a canceled state (if valid).
 */
- (void)cancel;

// private
@property (nonatomic, strong, readonly) NSMutableArray *eventQueue;
@end

SpecBegin(VELEventRecognizer)

    __block NSView *view;
    __block NSEvent *(^mouseEventAtLocation)(CGFloat, CGFloat);

    __block TestEventRecognizer *recognizer;

    before(^{
        view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 1000)];
        expect(view).not.toBeNil();

        mouseEventAtLocation = [^(CGFloat x, CGFloat y){
            CGPoint point = CGPointMake(x, y);

            CGEventRef cgEvent = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, point, kCGMouseButtonLeft);
            expect(cgEvent).not.toBeNil();

            NSEvent *event = [NSEvent eventWithCGEvent:cgEvent];
            CFRelease(cgEvent);

            expect(event).not.toBeNil();
            return event;
        } copy];
    });

    before(^{
        recognizer = [[TestEventRecognizer alloc] init];
        expect(recognizer).not.toBeNil();

        expect(recognizer.view).toBeNil();
        expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
        expect(recognizer.active).toBeFalsy();
        expect(recognizer.enabled).toBeTruthy();
        expect(recognizer.recognizersRequiredToFail).toBeNil();
        expect(recognizer.delaysEventDelivery).toBeFalsy();
        expect(recognizer.didReset).toBeFalsy();
        expect(recognizer.willTransitionInvoked).toBeFalsy();

        recognizer.view = view;
        expect(recognizer.view).toEqual(view);
    });

    after(^{
        recognizer = nil;
    });

    it(@"should be released when view is released", ^{
        __weak VELEventRecognizer *weakRecognizer = recognizer;
        expect(weakRecognizer).not.toBeNil();

        recognizer = nil;
        expect(weakRecognizer).not.toBeNil();

        view = nil;
        expect(weakRecognizer).toBeNil();
    });

    it(@"should register an action block", ^{
        __weak VELEventRecognizer *weakRecognizer = recognizer;

        id block = ^(VELEventRecognizer *recognizer){
            expect(recognizer).toEqual(weakRecognizer);
        };

        id action = [recognizer addActionUsingBlock:block];
        expect(action).not.toBeNil();

        [recognizer removeAction:action];
    });

    it(@"should return recognizers for view", ^{
        NSArray *recognizers = [VELEventRecognizer eventRecognizersForView:view];
        expect(recognizers).toEqual([NSArray arrayWithObject:recognizer]);
    });

    it(@"should return nil recognizers for view without any", ^{
        NSView *anotherView = [[NSView alloc] initWithFrame:CGRectZero];

        NSArray *recognizers = [VELEventRecognizer eventRecognizersForView:anotherView];
        expect(recognizers).toBeNil();
    });

    describe(@"one event to recognize", ^{
        __block NSEvent *event;
        __block NSEvent *unrecognizedEvent;

        before(^{
            event = mouseEventAtLocation(50, 25);
            recognizer.eventsToRecognize = [NSArray arrayWithObject:event];

            unrecognizedEvent = mouseEventAtLocation(-1, -5);

            expect(recognizer.discrete).toBeTruthy();
            expect(recognizer.continuous).toBeFalsy();
        });

        it(@"should recognize a discrete event", ^{
            __block BOOL invoked = NO;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateRecognized);
                expect(recognizer.active).toBeTruthy();

                invoked = YES;
            }];

            expect([^{
                [recognizer handleEvent:event];
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invoked).toBeTruthy();
            expect(recognizer.didReset).toBeFalsy();
        });

        it(@"should do nothing while disabled", ^{
            __block BOOL invoked = NO;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                invoked = YES;
            }];

            recognizer.enabled = NO;

            expect([^{
                [recognizer handleEvent:event];
            } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

            expect([^{
                [recognizer handleEvent:unrecognizedEvent];
            } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invoked).toBeFalsy();
        });

        it(@"should transition back to possible state after recognition", ^{
            __block BOOL invoked = NO;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateRecognized);
                expect(recognizer.active).toBeTruthy();

                [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                    expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
                    expect(recognizer.active).toBeFalsy();

                    invoked = YES;
                }];
            }];

            expect([^{
                [recognizer handleEvent:event];
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invoked).isGoing.toBeTruthy();
            expect(recognizer.didReset).toBeTruthy();
        });

        it(@"should fail to recognize an invalid discrete event", ^{
            __block BOOL invoked = NO;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateFailed);
                expect(recognizer.active).toBeFalsy();

                invoked = YES;
            }];

            expect([^{
                [recognizer handleEvent:unrecognizedEvent];
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invoked).toBeTruthy();
            expect(recognizer.didReset).toBeFalsy();
        });

        it(@"should transition back to possible state after failure", ^{
            __block BOOL invoked = NO;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateFailed);
                expect(recognizer.active).toBeFalsy();

                [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                    expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
                    expect(recognizer.active).toBeFalsy();

                    invoked = YES;
                }];
            }];

            expect([^{
                [recognizer handleEvent:unrecognizedEvent];
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invoked).isGoing.toBeTruthy();
            expect(recognizer.didReset).toBeTruthy();
        });

        it(@"should not invoke action block after being removed", ^{
            __block BOOL invoked = NO;

            id action = [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                invoked = YES;
            }];

            [recognizer removeAction:action];
            [recognizer handleEvent:event];

            expect(invoked).toBeFalsy();
        });

        it(@"should remove just one action block", ^{
            __block BOOL firstInvoked = NO;
            __block BOOL secondInvoked = NO;

            id action = [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                firstInvoked = YES;
            }];

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                secondInvoked = YES;
            }];

            [recognizer removeAction:action];
            [recognizer handleEvent:event];

            expect(firstInvoked).toBeFalsy();
            expect(secondInvoked).toBeTruthy();
        });

        describe(@"continuous event", ^{
            __block NSEvent *continuousEvent;

            __block BOOL began;
            __block BOOL changed;
            __block BOOL ended;
            __block BOOL cancelled;

            before(^{
                recognizer.continuousEvent = continuousEvent = mouseEventAtLocation(100, 85);

                expect(recognizer.discrete).toBeFalsy();
                expect(recognizer.continuous).toBeTruthy();

                began = NO;
                changed = NO;
                ended = NO;
                cancelled = NO;

                [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                    switch (recognizer.state) {
                        case VELEventRecognizerStateBegan:
                            expect(recognizer.active).toBeTruthy();

                            began = YES;
                            break;

                        case VELEventRecognizerStateChanged:
                            expect(began).toBeTruthy();
                            expect(recognizer.active).toBeTruthy();

                            changed = YES;
                            break;

                        case VELEventRecognizerStateEnded:
                            expect(began).toBeTruthy();
                            expect(recognizer.active).toBeTruthy();

                            ended = YES;
                            break;

                        case VELEventRecognizerStateCancelled:
                            expect(began).toBeTruthy();
                            expect(recognizer.active).toBeFalsy();

                            cancelled = YES;
                            break;

                        default:
                            ;
                    }
                }];
            });

            it(@"should do nothing while disabled", ^{
                __block BOOL invoked = NO;

                [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                    invoked = YES;
                }];

                recognizer.enabled = NO;

                expect([^{
                    [recognizer handleEvent:event];
                } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

                expect([^{
                    [recognizer handleEvent:continuousEvent];
                } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

                expect([^{
                    [recognizer handleEvent:unrecognizedEvent];
                } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

                expect(invoked).toBeFalsy();
            });

            it(@"should recognize a continuous event", ^{
                expect([^{
                    [recognizer handleEvent:event];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeFalsy();

                for (unsigned i = 0; i < 3; ++i) {
                    expect([^{
                        [recognizer handleEvent:continuousEvent];
                    } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                    expect(began).toBeTruthy();
                    expect(changed).toBeTruthy();
                    expect(ended).toBeFalsy();
                    expect(cancelled).toBeFalsy();
                }

                expect([^{
                    [recognizer handleEvent:unrecognizedEvent];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeTruthy();
                expect(ended).toBeTruthy();
                expect(cancelled).toBeFalsy();

                expect(recognizer.didReset).toBeFalsy();
                expect(recognizer.state).isGoing.toEqual(VELEventRecognizerStatePossible);
                expect(recognizer.didReset).toBeTruthy();

                expect(began).toBeTruthy();
                expect(changed).toBeTruthy();
                expect(ended).toBeTruthy();
                expect(cancelled).toBeFalsy();
            });

            it(@"should cancel a continuous event", ^{
                expect([^{
                    [recognizer handleEvent:event];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeFalsy();

                expect([^{
                    [recognizer cancel];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeTruthy();

                expect(recognizer.didReset).toBeFalsy();
                expect(recognizer.state).isGoing.toEqual(VELEventRecognizerStatePossible);
                expect(recognizer.didReset).toBeTruthy();

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeTruthy();
            });

            it(@"should end a continuous event even without an intervening change", ^{
                expect([^{
                    [recognizer handleEvent:event];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeFalsy();

                expect([^{
                    [recognizer handleEvent:unrecognizedEvent];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeTruthy();
                expect(cancelled).toBeFalsy();

                expect(recognizer.didReset).toBeFalsy();
                expect(recognizer.state).isGoing.toEqual(VELEventRecognizerStatePossible);
                expect(recognizer.didReset).toBeTruthy();

                expect(began).toBeTruthy();
                expect(changed).toBeFalsy();
                expect(ended).toBeTruthy();
                expect(cancelled).toBeFalsy();
            });

            it(@"should fail to recognize an invalid continuous event", ^{
                expect(recognizer.didReset).toBeFalsy();

                expect([^{
                    [recognizer handleEvent:unrecognizedEvent];
                } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

                expect(began).toBeFalsy();
                expect(changed).toBeFalsy();
                expect(ended).toBeFalsy();
                expect(cancelled).toBeFalsy();

                expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
                expect(recognizer.didReset).toBeTruthy();
            });
        });
    });

    describe(@"multiple events to recognize", ^{
        __block NSEvent *unrecognizedEvent;
        __block void (^sendEvents)(NSArray *);

        before(^{
            recognizer.eventsToRecognize = [NSArray arrayWithObjects:
                mouseEventAtLocation(50, 25),
                mouseEventAtLocation(11, 23),
                mouseEventAtLocation(80, 111),
                nil
            ];

            unrecognizedEvent = mouseEventAtLocation(-1, -5);

            expect(recognizer.discrete).toBeTruthy();
            expect(recognizer.continuous).toBeFalsy();

            sendEvents = [^(NSArray *array){
                [array enumerateObjectsUsingBlock:^(NSEvent *event, NSUInteger index, BOOL *stop){
                    expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
                    expect(recognizer.active).toBeFalsy();

                    [recognizer handleEvent:event];
                }];
            } copy];
        });

        it(@"should recognize a discrete event", ^{
            __block NSUInteger invokeCount = 0;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateRecognized);
                expect(recognizer.active).toBeTruthy();

                ++invokeCount;
            }];

            expect([^{
                sendEvents(recognizer.eventsToRecognize);
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invokeCount).toEqual(1);
        });

        it(@"should not recognize an incomplete discrete event", ^{
            __block NSUInteger invokeCount = 0;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                ++invokeCount;
            }];

            NSArray *partialEvents = [recognizer.eventsToRecognize subarrayWithRange:NSMakeRange(0, recognizer.eventsToRecognize.count - 1)];

            expect([^{
                sendEvents(partialEvents);
            } copy]).not.toInvoke(recognizer, @selector(willTransitionToState:));

            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
            expect(recognizer.didReset).toBeFalsy();

            expect(invokeCount).toEqual(0);
        });

        it(@"should fail to recognize an invalid discrete event", ^{
            __block NSUInteger invokeCount = 0;

            [recognizer addActionUsingBlock:^(VELEventRecognizer *recognizer){
                expect(recognizer.state).toEqual(VELEventRecognizerStateFailed);
                expect(recognizer.active).toBeFalsy();

                ++invokeCount;
            }];

            NSMutableArray *events = [recognizer.eventsToRecognize mutableCopy];
            [events removeLastObject];
            [events addObject:unrecognizedEvent];

            expect([^{
                sendEvents(events);
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(invokeCount).toEqual(1);
            expect(recognizer.didReset).toBeFalsy();
        });
    });

    describe(@"event recognizer dependencies", ^{
        __block NSEvent *event;
        __block NSEvent *unrecognizedEvent;

        __block TestEventRecognizer *firstDependency;
        __block TestEventRecognizer *secondDependency;

        before(^{
            event = mouseEventAtLocation(50, 25);
            unrecognizedEvent = mouseEventAtLocation(-1, -5);

            NSArray *eventsToRecognize = [NSArray arrayWithObject:event];

            firstDependency = [[TestEventRecognizer alloc] init];
            expect(firstDependency).not.toBeNil();

            secondDependency = [[TestEventRecognizer alloc] init];
            expect(secondDependency).not.toBeNil();

            firstDependency.eventsToRecognize = eventsToRecognize;
            secondDependency.eventsToRecognize = eventsToRecognize;
            recognizer.eventsToRecognize = eventsToRecognize;

            NSSet *dependencies = [NSSet setWithObjects:firstDependency, secondDependency, nil];

            recognizer.recognizersRequiredToFail = dependencies;
            expect(recognizer.recognizersRequiredToFail).toEqual(dependencies);
        });

        it(@"should not handle events before all dependencies fail", ^{
            [recognizer handleEvent:event];
            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
        });

        it(@"should not handle events while any dependency has not failed", ^{
            [firstDependency handleEvent:unrecognizedEvent];
            expect(firstDependency.state).toEqual(VELEventRecognizerStateFailed);

            [recognizer handleEvent:event];
            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
        });

        it(@"should handle events after all dependencies have failed", ^{
            [firstDependency handleEvent:unrecognizedEvent];
            expect(firstDependency.state).toEqual(VELEventRecognizerStateFailed);

            [secondDependency handleEvent:unrecognizedEvent];
            expect(secondDependency.state).toEqual(VELEventRecognizerStateFailed);

            [recognizer handleEvent:event];
            expect(recognizer.state).toEqual(VELEventRecognizerStateRecognized);
        });

        it(@"should queue events until all dependencies have failed", ^{
            [recognizer handleEvent:event];
            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);

            [firstDependency handleEvent:unrecognizedEvent];
            expect(firstDependency.state).toEqual(VELEventRecognizerStateFailed);

            expect([^{
                [secondDependency handleEvent:unrecognizedEvent];
            } copy]).toInvoke(recognizer, @selector(willTransitionToState:));

            expect(secondDependency.state).toEqual(VELEventRecognizerStateFailed);
            expect(recognizer.state).toEqual(VELEventRecognizerStateRecognized);
        });

        it(@"should not handle events after dependencies, even if they later fail", ^{
            [recognizer handleEvent:event];
            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);

            [firstDependency handleEvent:event];
            expect(firstDependency.state).toEqual(VELEventRecognizerStateRecognized);

            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);

            [firstDependency handleEvent:unrecognizedEvent];
            [secondDependency handleEvent:unrecognizedEvent];

            expect(recognizer.state).toEqual(VELEventRecognizerStatePossible);
        });
    });

SpecEnd

@implementation TestEventRecognizer

#pragma mark Properties

@synthesize eventsToRecognize = m_eventsToRecognize;
@synthesize continuousEvent = m_continuousEvent;
@synthesize eventQueue = m_eventQueue;
@synthesize willTransitionInvoked = m_willTransitionInvoked;
@synthesize didReset = m_didReset;

- (BOOL)isContinuous {
    return self.continuousEvent != nil;
}

- (BOOL)isDiscrete {
    return self.continuousEvent == nil;
}

#pragma mark Lifecycle

- (id)init {
    self = [super init];
    if (!self)
        return nil;

    m_eventQueue = [NSMutableArray array];
    return self;
}

#pragma mark Event Handling

- (void)handleEvent:(NSEvent *)event; {
    NSParameterAssert(event != nil);

    [super handleEvent:event];

    // should not be receiving events in these states
    expect(self.state).not.toEqual(VELEventRecognizerStateEnded);
    expect(self.state).not.toEqual(VELEventRecognizerStateCancelled);
    expect(self.state).not.toEqual(VELEventRecognizerStateFailed);

    switch (self.state) {
        case VELEventRecognizerStatePossible: {
            [self.eventQueue addObject:event];

            __block BOOL failed = NO;
            [self.eventQueue enumerateObjectsUsingBlock:^(NSEvent *event, NSUInteger index, BOOL *stop){
                if (index < self.eventsToRecognize.count && [[self.eventsToRecognize objectAtIndex:index] isEqual:event])
                    return;

                // got an event that's invalid, fail to recognize
                if (self.discrete)
                    self.state = VELEventRecognizerStateFailed;

                [self reset];
                failed = YES;
                *stop = YES;
            }];

            // if we failed or are not done recognizing yet
            if (failed || self.eventQueue.count != self.eventsToRecognize.count)
                break;

            // recognized all events (we already checked the objects themselves
            // in the above loop)
            if (self.continuous)
                self.state = VELEventRecognizerStateBegan;
            else
                self.state = VELEventRecognizerStateRecognized;

            break;
        }

        case VELEventRecognizerStateBegan:
        case VELEventRecognizerStateChanged:
            if ([event isEqual:self.continuousEvent])
                self.state = VELEventRecognizerStateChanged;
            else
                self.state = VELEventRecognizerStateEnded;

            break;

        default:
            ;
    }
}

#pragma mark States and Transitions

- (void)cancel; {
    if (self.state == VELEventRecognizerStateBegan || self.state == VELEventRecognizerStateChanged)
        self.state = VELEventRecognizerStateCancelled;
}

- (void)willTransitionToState:(VELEventRecognizerState)toState; {
    [super willTransitionToState:toState];

    expect(self.willTransitionInvoked).not.toBeTruthy();
    self.willTransitionInvoked = YES;

    switch (toState) {
        case VELEventRecognizerStatePossible:
            expect(self.state).not.toEqual(VELEventRecognizerStateBegan);
            expect(self.state).not.toEqual(VELEventRecognizerStateChanged);
            expect(self.state).not.toEqual(VELEventRecognizerStatePossible);
            break;

        case VELEventRecognizerStateBegan:
            expect(self.continuous).toBeTruthy();
            expect(self.state).toEqual(VELEventRecognizerStatePossible);
            break;

        case VELEventRecognizerStateEnded:
            if (self.discrete) {
                // this is actually VELEventRecognizerStateRecognized
                expect(self.state).toEqual(VELEventRecognizerStatePossible);
                break;
            }

        case VELEventRecognizerStateChanged:
        case VELEventRecognizerStateCancelled:
            expect(self.continuous).toBeTruthy();
            expect(self.state == VELEventRecognizerStateBegan || self.state == VELEventRecognizerStateChanged).toBeTruthy();
            break;

        case VELEventRecognizerStateFailed:
            expect(self.discrete).toBeTruthy();
            expect(self.state).toEqual(VELEventRecognizerStatePossible);
            break;

        default:
            NSAssert(NO, @"Invalid to state: %i", (int)toState);
    }
}

- (void)didTransitionFromState:(VELEventRecognizerState)fromState; {
    [super didTransitionFromState:fromState];

    expect(self.willTransitionInvoked).toBeTruthy();
    self.willTransitionInvoked = NO;

    if (fromState != VELEventRecognizerStateChanged)
        expect(self.state).not.toEqual(fromState);

    expect(self.active).toEqual(self.state == VELEventRecognizerStateBegan || self.state == VELEventRecognizerStateChanged || self.state == VELEventRecognizerStateEnded);
}

- (void)reset {
    [super reset];
    self.didReset = YES;
}

@end
