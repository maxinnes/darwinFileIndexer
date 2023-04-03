#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import <unistd.h>

// Declare a global variable for the SQLite database
sqlite3 *database;

// Declare a global variable for progress tracking
NSProgress *progress;

// Declare global variables for batch size and the current batch
NSUInteger batchSize = 1000;
NSUInteger currentBatch = 0;

// Function to create a table in the SQLite database
void createTable() {
    char *error;
    const char *sql = "CREATE TABLE IF NOT EXISTS file_info (id INTEGER PRIMARY KEY AUTOINCREMENT, inode INTEGER, owner TEXT, permissions TEXT, path TEXT, created_date TEXT, modified_date TEXT, size INTEGER, isDirectory BOOLEAN NOT NULL);";
    if (sqlite3_exec(database, sql, NULL, NULL, &error) != SQLITE_OK) {
        NSLog(@"Failed to create table: %s", error);
        sqlite3_free(error);
    }
}

// Function to count the number of items in a directory
unsigned long long countItemsInDirectory(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:0 errorHandler:nil];

    unsigned long long count = 0;

    for (__unused NSURL *url in enumerator) {
        count++;
    }

    return count;
}

// Function to insert data into the SQLite database
void insertData(NSNumber *inode, NSString *owner, NSString *permissions, NSString *path, NSString *createdDate, NSString *modifiedDate, NSNumber *size, BOOL isDirectory) {
    NSString *sql = @"INSERT INTO file_info (inode, owner, permissions, path, created_date, modified_date, size, isDirectory) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
    sqlite3_stmt *statement;

    if (sqlite3_prepare_v2(database, [sql UTF8String], -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(statement, 1, [inode longLongValue]);
        sqlite3_bind_text(statement, 2, [owner UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, [permissions UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 4, [path UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 5, [createdDate UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 6, [modifiedDate UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(statement, 7, [size longLongValue]);
        sqlite3_bind_int(statement, 8, isDirectory ? 1 : 0);

        if (sqlite3_step(statement) != SQLITE_DONE) {
            NSLog(@"Error inserting data: %s", sqlite3_errmsg(database));
        }
    }

    sqlite3_finalize(statement);
}

// Recursive function to scan directories and collect file information
void scanDirectory(NSString *path, NSUInteger maxDepth, NSSet *excludeDirectories) {
    if (maxDepth == 0) {
        return;
    }

    if ([excludeDirectories containsObject:path]) {
        return;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *contents = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] options:0 error:&error];

    for (NSURL *url in contents) {
        // Check if it's time to commit the current batch
        if (currentBatch >= batchSize) {
            sqlite3_exec(database, "COMMIT;", 0, 0, 0);
            sqlite3_exec(database, "BEGIN;", 0, 0, 0);
            currentBatch = 0;
        }

        NSNumber *isDirectory;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error];

        NSDictionary *attributes = [fileManager attributesOfItemAtPath:url.path error:&error];
        NSNumber *inode = attributes[NSFileSystemFileNumber];
        NSString *owner = [NSString stringWithFormat:@"%@:%@", attributes[NSFileOwnerAccountName], attributes[NSFileGroupOwnerAccountName]];
        NSString *permissions = [NSString stringWithFormat:@"%lo", [attributes[NSFilePosixPermissions] integerValue]];
        NSString *createdDate = [NSString stringWithFormat:@"%@", attributes[NSFileCreationDate]];
        NSString *modifiedDate = [NSString stringWithFormat:@"%@", attributes[NSFileModificationDate]];
        NSNumber *size = attributes[NSFileSize];

        // Call the insertData function to insert the data into the SQLite database
        insertData(inode, owner, permissions, url.path, createdDate, modifiedDate, size, [isDirectory boolValue]);

        currentBatch++;

        // If the current item is a directory, call the scanDirectory
        if ([isDirectory boolValue]) {
            scanDirectory(url.path, maxDepth - 1, excludeDirectories);
        }
    }
}

// Main function
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Declare variables to store parsed arguments
        NSMutableSet *excludeDirectories = [NSMutableSet set];
        NSUInteger maxDepth = NSUIntegerMax;

        // Parse command-line arguments using getopt
        int opt;
        while ((opt = getopt(argc, (char **)argv, "e:d:")) != -1) {
            switch (opt) {
                case 'e':
                    [excludeDirectories addObject:[NSString stringWithUTF8String:optarg]];
                    break;
                case 'd':
                    maxDepth = strtoul(optarg, NULL, 10);
                    break;
                default:
                    NSLog(@"Usage: %s [-e exclude_directory] [-d max_depth]", argv[0]);
                    return 1;
            }
        }

        NSString *dbPath = [NSHomeDirectory() stringByAppendingPathComponent:@"file_info.db"];

        if (sqlite3_open([dbPath UTF8String], &database) == SQLITE_OK) {
            // Create a table in the SQLite database
            createTable();

            // Initialize progress and start counting items
            unsigned long long totalItems = countItemsInDirectory(@"/");
            progress = [NSProgress progressWithTotalUnitCount:totalItems];

            // Begin the transaction
            sqlite3_exec(database, "BEGIN;", 0, 0, 0);

            // Call the scanDirectory function to start scanning the root directory
            scanDirectory(@"/", maxDepth, excludeDirectories);

            // Commit the final batch
            sqlite3_exec(database, "COMMIT;", 0, 0, 0);

            printf("\n");
            sqlite3_close(database);
            NSLog(@"File and directory details saved to the SQLite database at %@", dbPath);
        } else {
            NSLog(@"Failed to open/create the SQLite database");
        }
    }
    return 0;
}
