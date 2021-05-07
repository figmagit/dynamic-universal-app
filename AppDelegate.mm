#import "AppDelegate.h"

#ifdef __aarch64__
#define ARCH_KEY_NAME @"aarch64"
#else
#define ARCH_KEY_NAME @"x86_64"
#endif

const NSTimeInterval kDefaultTimeoutSecs = 60 * 60 * 12;  // 12 hours

@interface AppDelegate ()
@property(weak) IBOutlet NSWindow* window;
@property(weak) IBOutlet NSTextField* label;
@property(weak) IBOutlet NSProgressIndicator* progressIndicator;

@property NSURLSessionDownloadTask* task;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  NSURLSession* session = [NSURLSession sharedSession];

  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  NSDictionary* downloadURLs = [info objectForKey:@"TargetDownloadURLs"];
  NSURL* downloadURL = [NSURL URLWithString:[downloadURLs valueForKey:ARCH_KEY_NAME]];
  NSString* targetAppName = [info valueForKey:@"TargetAppName"];

  self.window.title = [NSString stringWithFormat:@"%@ Installer", targetAppName];
  self.label.stringValue = [NSString stringWithFormat:@"Downloading %@...", targetAppName];

  // Fetch the platform specific build archive.
  NSURLRequest* request = [NSURLRequest requestWithURL:downloadURL
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:kDefaultTimeoutSecs];
  self.task = [session
      downloadTaskWithRequest:request
            completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
              if (error) {
                // TODO(poiru): Handle this.
                NSLog(@"Failed to save: %@", error);
                return;
              }

              dispatch_async(dispatch_get_main_queue(), ^{
                self.label.stringValue =
                    [NSString stringWithFormat:@"Installing %@...", targetAppName];
                self.progressIndicator.indeterminate = true;
              });

              // Big Sur and later have APIs to extract archives, but we need
              // to support older versions. Lets use plain old unzip to
              // extract the downloaded archive.
              //
              // TODO(poiru): Support XZ archives.
              // TODO(poiru): Handle error.
              NSTask* task = [[NSTask alloc] init];
              [task setLaunchPath:@"/usr/bin/unzip"];
              [task setArguments:@[ @"-qq", @"-o", @"-d", @"/Applications", location.path ]];
              [task launch];
              [task waitUntilExit];
              [[NSFileManager defaultManager] removeItemAtPath:location.path error:nil];

              dispatch_async(dispatch_get_main_queue(), ^{
                [self launchInstalledApp];
              });
            }];
  [self.task resume];

  [self.task.progress addObserver:self
                       forKeyPath:@"fractionCompleted"
                          options:NSKeyValueObservingOptionNew
                          context:nil];
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id>*)change
                       context:(void*)context {
  if ([keyPath isEqual:@"fractionCompleted"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      const auto value = [[change valueForKey:NSKeyValueChangeNewKey] doubleValue];
      self.progressIndicator.doubleValue = value;
    });
  }
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  [self.task cancel];
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  if (self.task.state == NSURLSessionTaskStateCompleted) {
    [self launchInstalledApp];
  }
}

- (IBAction)cancelClicked:(id)sender {
  [self.task cancel];
  [NSApp terminate:nullptr];
}

- (void)launchInstalledApp {
  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  NSString* targetAppName = [info valueForKey:@"TargetAppName"];

  // First check if trying to run `sh -c ...` works.
  NSTask* checkTask = [[NSTask alloc] init];
  [checkTask setLaunchPath:@"/bin/sh"];
  [checkTask setArguments:@[ @"-c", @"sleep 0 && which open" ]];
  [checkTask launch];
  [checkTask waitUntilExit];
  if (checkTask.terminationStatus != 0) {
    // TODO(poiru): Handle this.
    [NSApp terminate:nullptr];
    return;
  }

  // Spawn a sh process to relaunch the installed app after we exit. Otherwise
  // the new app might not launch if this stub app is already running at the
  // path.
  NSTask* launchTask = [[NSTask alloc] init];
  [launchTask setLaunchPath:@"/bin/sh"];
  [launchTask setArguments:@[
    @"-c", [NSString stringWithFormat:@"sleep 1; /usr/bin/open %s \"/Applications/%@.app\"",
                                      self.window.isMainWindow ? "" : "-g", targetAppName]
  ]];
  [launchTask launch];
  [NSApp terminate:nullptr];
}

@end