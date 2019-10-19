-- This table stores board information and board settings.
CREATE TABLE Boards (
  Name			TEXT		NOT NULL	UNIQUE	PRIMARY KEY			CHECK(LENGTH(Name) > 0 AND LENGTH(Name) <= 8),
  Title			TEXT		NOT NULL	UNIQUE					CHECK(LENGTH(Title) <= 32 AND LENGTH(Title) > 0),
  Subtitle		TEXT		NOT NULL						CHECK(LENGTH(Subtitle) <= 64),
  MaxPostNumber		INTEGER		NOT NULL				DEFAULT 0	CHECK(MaxPostNumber >= 0),
  Lock			BOOLEAN		NOT NULL				DEFAULT FALSE,
  DisplayOverboard	BOOLEAN		NOT NULL				DEFAULT TRUE,

  -- Notes:
  -- Setting an integer value to -1 disables the setting. For example, setting
  -- "TPHLimit" to -1 means that no limit on TPH is enforced.
  PostMaxImages		INTEGER		NOT NULL				DEFAULT 5	CHECK(PostMaxImages <= 5 AND PostMaxImages >= 0),
  ThreadMinLength	INTEGER		NOT NULL				DEFAULT 1,
  PostMaxLength		INTEGER		NOT NULL				DEFAULT 32768,
  PostMaxNewlines	INTEGER		NOT NULL				DEFAULT 64,
  PostMaxDblNewlines	INTEGER		NOT NULL				DEFAULT 16,
  TPHLimit		INTEGER		NOT NULL				DEFAULT -1,
  PPHLimit		INTEGER		NOT NULL				DEFAULT -1,
  ThreadCaptcha		BOOLEAN		NOT NULL				DEFAULT FALSE,
  PostCaptcha		BOOLEAN		NOT NULL				DEFAULT FALSE,
  CaptchaTriggerTPH	INTEGER		NOT NULL				DEFAULT -1,
  CaptchaTriggerPPH	INTEGER		NOT NULL				DEFAULT -1,
  BumpLimit		INTEGER		NOT NULL				DEFAULT 1000	CHECK(BumpLimit <= 1000 AND BumpLimit >= 0),
  PostLimit		INTEGER		NOT NULL				DEFAULT 1000	CHECK(PostLimit <= 1000 AND PostLimit >= 0),
  ThreadLimit		INTEGER		NOT NULL				DEFAULT 1000	CHECK(ThreadLimit <= 1000 AND ThreadLimit > 0)
);

CREATE TABLE Posts (
  Board			TEXT		NOT NULL,
  Number		INTEGER							DEFAULT NULL,
  Parent		INTEGER							DEFAULT NULL,
  Date			DATETIME	NOT NULL				DEFAULT 0,
  LastBumpDate		DATETIME	NOT NULL				DEFAULT 0	CHECK(LastBumpDate >= Date),
  Name			TEXT		NOT NULL				DEFAULT 'Anonymous' CHECK(LENGTH(Name) <= 64),
  Email			TEXT		NOT NULL				DEFAULT ''	CHECK(LENGTH(Email) <= 64),
  Subject		TEXT		NOT NULL				DEFAULT ''	CHECK(LENGTH(Subject) <= 64),
  Comment		TEXT		NOT NULL				DEFAULT ''	CHECK(LENGTH(Comment) <= 32768),
  Sticky		BOOLEAN		NOT NULL				DEFAULT FALSE,
  Lock			BOOLEAN		NOT NULL				DEFAULT FALSE,
  Autosage		BOOLEAN		NOT NULL				DEFAULT FALSE,
  Cycle			BOOLEAN		NOT NULL				DEFAULT FALSE,

  PRIMARY KEY (Board, Number),
  FOREIGN KEY (Board) REFERENCES Boards(Name),
  FOREIGN KEY (Board, Parent) REFERENCES Posts (Board, Number),
  UNIQUE (Board, Number)
);

CREATE TABLE Refs (
  Board                 TEXT            NOT NULL,
  Referee               INTEGER         NOT NULL,
  Referrer              INTEGER         NOT NULL,

  PRIMARY KEY (Board, Referee, Referrer),
  FOREIGN KEY (Board, Referee) REFERENCES Posts (Board, Number),
  FOREIGN KEY (Board, Referrer) REFERENCES Posts (Board, Number),
  CHECK(Referee != Referrer)
) WITHOUT ROWID;

CREATE TABLE FileRefs (
  Board			TEXT		NOT NULL,
  Number		INTEGER		NOT NULL,
  File			TEXT		NOT NULL,
  Sequence		INTEGER		NOT NULL,

  PRIMARY KEY (Board, Number, Sequence),
  FOREIGN KEY (Board, Number) REFERENCES Posts (Board, Number),
  FOREIGN KEY (File) REFERENCES Files (Name)
) WITHOUT ROWID;

CREATE TABLE Files (
  Name			TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Name) > 0),
  Size			INTEGER		NOT NULL						CHECK(Size > 0 AND Size <= 16777216),
  Width                 INTEGER                                                 DEFAULT NULL,
  Height                INTEGER                                                 DEFAULT NULL,

  CHECK((Width IS NOT NULL AND Height IS NOT NULL) OR (Width IS NULL AND Height IS NULL))
) WITHOUT ROWID;

CREATE TABLE GlobalConfig (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY,
  Value                 NUMERIC
) WITHOUT ROWID;

CREATE TABLE Accounts (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Name) > 0 AND LENGTH(Name) <= 16),
  Type                  TEXT            NOT NULL,
  Board                 TEXT,
  PwHash                TEXT            NOT NULL,

  FOREIGN KEY (Board) REFERENCES Boards (Name),
  CHECK((Type IN ('admin', 'gvol') AND Board IS NULL) OR (Type IN ('bo', 'lvol') AND Board IS NOT NULL))
) WITHOUT ROWID;

CREATE TABLE Sessions (
  Key                   TEXT            NOT NULL        UNIQUE  PRIMARY KEY			CHECK(LENGTH(Key) = 16),
  Account               TEXT            NOT NULL        UNIQUE,
  ExpireDate            DATETIME        NOT NULL				DEFAULT 0,

  FOREIGN KEY (Account) REFERENCES Accounts (Name)
) WITHOUT ROWID;

CREATE TABLE Logs (
  Account               TEXT            NOT NULL				DEFAULT 'SYSTEM',
  Board                 TEXT            NOT NULL				DEFAULT 'GLOBAL',
  Date                  DATETIME        NOT NULL				DEFAULT 0,
  Description           TEXT            NOT NULL                                                CHECK(LENGTH(Description) > 0)
);

CREATE TABLE Captchas (
  Id			TEXT		NOT NULL	UNIQUE	PRIMARY KEY			CHECK(LENGTH(Id) = 16),
  Text			TEXT		NOT NULL						CHECK(LENGTH(Text) = 6),
  ExpireDate		DATETIME	NOT NULL				DEFAULT 0
) WITHOUT ROWID;

CREATE TRIGGER delete_child_posts BEFORE DELETE ON Posts WHEN OLD.Parent IS NULL
BEGIN
  DELETE FROM Posts WHERE Board = OLD.Board AND Parent = OLD.Number;
END;

CREATE TRIGGER bump_thread AFTER INSERT ON Posts
  WHEN NEW.Parent IS NOT NULL AND NEW.Email NOT LIKE '%sage%'
   AND (SELECT COUNT(*) FROM Posts WHERE Parent = NEW.Parent) <= (SELECT BumpLimit FROM Boards WHERE Name = NEW.Board)
BEGIN
  UPDATE Posts SET LastBumpDate = STRFTIME('%s', 'now') WHERE Board = NEW.Board AND Number = NEW.Parent AND Autosage = FALSE;
END;

CREATE TRIGGER user_autosage AFTER INSERT ON Posts WHEN NEW.Parent IS NULL AND NEW.Email LIKE '%sage%'
BEGIN
  UPDATE Posts SET Autosage = TRUE WHERE rowid = NEW.rowid;
END;

CREATE TRIGGER cleanup_deleted_board BEFORE DELETE ON Boards
BEGIN
  DELETE FROM Posts WHERE Board = OLD.Name;
  DELETE FROM Accounts WHERE Board = OLD.Name;
END;

CREATE TRIGGER increment_post_number AFTER INSERT ON Posts
BEGIN
  UPDATE Posts SET Number = (SELECT MaxPostNumber + 1 FROM Boards WHERE Name = NEW.Board) WHERE rowid = NEW.rowid;
  UPDATE Boards SET MaxPostNumber = MaxPostNumber + 1 WHERE Name = NEW.Board;
END;

CREATE TRIGGER auto_enable_captcha_per_thread AFTER INSERT ON Posts
  WHEN NEW.Parent IS NULL
   AND (SELECT ThreadCaptcha FROM Boards WHERE Name = NEW.Board) = FALSE
   AND (SELECT COUNT(*) FROM Posts WHERE Board = NEW.Board AND Parent IS NULL AND Date > (STRFTIME('%s', 'now') - 3600))
       > (SELECT CaptchaTriggerTPH FROM Boards WHERE Name = NEW.Board)
   AND (SELECT CaptchaTriggerPPH FROM Boards WHERE Name = NEW.Board) > 0
BEGIN
  UPDATE Boards SET ThreadCaptcha = TRUE WHERE Name = NEW.Board;
  INSERT INTO Logs (Board, Date, Description) VALUES (NEW.Board, STRFTIME('%s', 'now'),
                                                      'Automatically enabled per-thread captcha due to excessive TPH');
END;

CREATE TRIGGER auto_enable_captcha_per_post AFTER INSERT ON Posts
  WHEN (SELECT PostCaptcha FROM Boards WHERE Name = NEW.Board) = FALSE
   AND (SELECT COUNT(*) FROM Posts WHERE Board = NEW.Board AND Date > (STRFTIME('%s', 'now') - 3600))
       > (SELECT CaptchaTriggerPPH FROM Boards WHERE Name = NEW.Board)
   AND (SELECT CaptchaTriggerPPH FROM Boards WHERE Name = NEW.Board) > 0
BEGIN
  UPDATE Boards SET PostCaptcha = TRUE WHERE Name = NEW.Board;
  INSERT INTO Logs (Board, Date, Description) VALUES (New.Board, STRFTIME('%s', 'now'),
                                                      'Automatically enabled per-post captcha due to excessive PPH');
END;

CREATE TRIGGER delete_cyclical AFTER INSERT ON Posts
  WHEN (SELECT Cycle FROM Posts WHERE Board = NEW.Board AND Number = NEW.Parent) = TRUE
   AND (SELECT COUNT(*) FROM Posts WHERE Parent = NEW.Parent) >= (SELECT PostLimit FROM Boards WHERE Name = NEW.Board)
BEGIN
  DELETE FROM Posts WHERE Board = NEW.Board AND Number = (SELECT MIN(Number) FROM Posts WHERE Parent = NEW.Parent);
END;

CREATE TRIGGER remove_old_refs BEFORE DELETE ON Posts
BEGIN
  DELETE FROM Refs WHERE Board = OLD.Board AND (Referee = OLD.Number OR Referrer = OLD.Number);
END;

CREATE TRIGGER remove_file_refs BEFORE DELETE ON Files
BEGIN
  DELETE FROM FileRefs WHERE File = OLD.Name;
END;

CREATE TRIGGER delete_old_sessions BEFORE INSERT ON Sessions
BEGIN
  DELETE FROM Sessions WHERE Account = NEW.Account;
END;

CREATE TRIGGER delete_sessions BEFORE DELETE ON Accounts
BEGIN
  DELETE FROM Sessions WHERE Account = OLD.Name;
END;

CREATE TRIGGER set_session_expiry AFTER INSERT ON Sessions
BEGIN
  UPDATE Sessions SET ExpireDate = STRFTIME('%s', 'now') + 86400 WHERE Key = NEW.Key;
END;

CREATE TRIGGER set_log_date AFTER INSERT ON Logs
BEGIN
  UPDATE Logs SET Date = STRFTIME('%s', 'now') WHERE rowid = NEW.rowid;
END;

CREATE TRIGGER set_post_date AFTER INSERT ON Posts
BEGIN
  UPDATE Posts SET Date = STRFTIME('%s', 'now'), LastBumpDate = STRFTIME('%s', 'now') WHERE rowid = NEW.rowid;
END;

CREATE TRIGGER set_captcha_expiry AFTER INSERT ON Captchas
BEGIN
  UPDATE Captchas SET ExpireDate = STRFTIME('%s', 'now') + 1800 WHERE Id = NEW.Id;
END;

-- This is a default account. You should use this only for setup purposes.
-- The setup account should be DELETED after use.
-- The initial password is 'password'.
INSERT INTO Accounts (Name, Type, PwHash) VALUES ('setup', 'admin', '$2b$14$7zJicITlut7XR.LQ3trgNOmNDBCispQWgYfxVpexfA3.A/XCl1oYK');
INSERT INTO GlobalConfig VALUES ('sitename', 'Picochan');
INSERT INTO GlobalConfig VALUES ('defaultpostname', 'Anonymous');
