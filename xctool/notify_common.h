//
//  notify_common.h
//  xctool
//
//  Created by Keqiu Hu on 7/31/16.
//  Copyright © 2016 Facebook, Inc. All rights reserved.
//

#ifndef notify_common_h
#define notify_common_h

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <notify.h>

#define PREFIX "com.osxbook.notification."
#define NOTIFICATION_BY_FILE_DESCRIPTOR PREFIX "descriptor"
#define NOTIFICATION_BY_MACH_PORT       PREFIX "mach_port"
#define NOTIFICATION_BY_SIGNAL          PREFIX "signal"

#define NOTIFICATION_CANCEL             PREFIX "cancel"

#endif /* notify_common_h */
