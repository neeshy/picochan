PRAGMA application_id = 37564;
PRAGMA user_version = 1;

CREATE TABLE Boards (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Name) BETWEEN 1 AND 8),
  Title                 TEXT            NOT NULL        UNIQUE                                  CHECK(LENGTH(Title) BETWEEN 1 AND 32),
  Subtitle              TEXT            NOT NULL                                                CHECK(LENGTH(Subtitle) <= 64),
  MaxPostNumber         INTEGER         NOT NULL                                DEFAULT 0       CHECK(MaxPostNumber >= 0),
  Lock                  BOOLEAN         NOT NULL                                DEFAULT FALSE,
  DisplayOverboard      BOOLEAN         NOT NULL                                DEFAULT TRUE,
  PostMaxFiles          INTEGER         NOT NULL                                DEFAULT 5       CHECK(PostMaxFiles BETWEEN 0 AND 5),
  ThreadMinLength       INTEGER         NOT NULL                                DEFAULT 1,
  PostMaxLength         INTEGER         NOT NULL                                DEFAULT 8192    CHECK(PostMaxLength <= 32768),
  PostMaxNewlines       INTEGER         NOT NULL                                DEFAULT 64      CHECK(PostMaxNewlines <= 1024),
  PostMaxDblNewlines    INTEGER         NOT NULL                                DEFAULT 16      CHECK(PostMaxDblNewlines <= 512),
  TPHLimit              INTEGER         NOT NULL                                DEFAULT -1,
  PPHLimit              INTEGER         NOT NULL                                DEFAULT -1,
  ThreadCaptcha         BOOLEAN         NOT NULL                                DEFAULT FALSE,
  PostCaptcha           BOOLEAN         NOT NULL                                DEFAULT FALSE,
  CaptchaTriggerTPH     INTEGER         NOT NULL                                DEFAULT -1,
  CaptchaTriggerPPH     INTEGER         NOT NULL                                DEFAULT -1,
  BumpLimit             INTEGER         NOT NULL                                DEFAULT 200     CHECK(BumpLimit BETWEEN 0 AND 1000),
  PostLimit             INTEGER         NOT NULL                                DEFAULT 250     CHECK(PostLimit BETWEEN 0 AND 1000),
  ThreadLimit           INTEGER         NOT NULL                                DEFAULT 500     CHECK(ThreadLimit BETWEEN 1 AND 1000)
) WITHOUT ROWID;

CREATE TABLE Posts (
  Board                 TEXT            NOT NULL,
  Number                INTEGER                                                 DEFAULT NULL,
  Parent                INTEGER                                                 DEFAULT NULL,
  Date                  DATETIME        NOT NULL                                DEFAULT 0,
  LastBumpDate          DATETIME        NOT NULL                                DEFAULT 0       CHECK(LastBumpDate >= Date),
  Name                  TEXT            NOT NULL                                DEFAULT 'Anonymous' CHECK(LENGTH(Name) <= 64),
  Email                 TEXT            NOT NULL                                DEFAULT ''      CHECK(LENGTH(Email) <= 64),
  Subject               TEXT            NOT NULL                                DEFAULT ''      CHECK(LENGTH(Subject) <= 64),
  Capcode               TEXT                                                    DEFAULT NULL,
  CapcodeBoard          TEXT                                                    DEFAULT NULL,
  Comment               TEXT            NOT NULL                                DEFAULT ''      CHECK(LENGTH(Comment) <= 32768),
  Sticky                BOOLEAN         NOT NULL                                DEFAULT FALSE,
  Lock                  BOOLEAN         NOT NULL                                DEFAULT FALSE,
  Autosage              BOOLEAN         NOT NULL                                DEFAULT FALSE,
  Cycle                 BOOLEAN         NOT NULL                                DEFAULT FALSE,
  ReplyCount            INTEGER                                                 DEFAULT NULL    CHECK(ReplyCount IS NULL OR ReplyCount >= 0),

  PRIMARY KEY (Board, Number),
  FOREIGN KEY (Board) REFERENCES Boards(Name) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (Board, Parent) REFERENCES Posts (Board, Number) ON UPDATE CASCADE ON DELETE CASCADE,
  CHECK((Capcode IN ('admin', 'gvol') AND CapcodeBoard IS NULL) OR (Capcode IN ('bo', 'lvol') AND Capcode IS NOT NULL))
);

CREATE TABLE Refs (
  Board                 TEXT            NOT NULL,
  Referee               INTEGER         NOT NULL,
  Referrer              INTEGER         NOT NULL,

  PRIMARY KEY (Board, Referee, Referrer),
  FOREIGN KEY (Board, Referee) REFERENCES Posts (Board, Number) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (Board, Referrer) REFERENCES Posts (Board, Number) ON UPDATE CASCADE ON DELETE CASCADE,
  CHECK(Referee != Referrer)
) WITHOUT ROWID;

CREATE TABLE FileRefs (
  Board                 TEXT            NOT NULL,
  Number                INTEGER         NOT NULL,
  File                  TEXT            NOT NULL,
  Name                  TEXT            NOT NULL,
  Spoiler               BOOLEAN         NOT NULL,
  Sequence              INTEGER         NOT NULL,

  PRIMARY KEY (Board, Number, Sequence),
  FOREIGN KEY (Board, Number) REFERENCES Posts (Board, Number) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (File) REFERENCES Files (Name) ON UPDATE CASCADE ON DELETE CASCADE
) WITHOUT ROWID;

CREATE TABLE Files (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Name) BETWEEN 130 AND 133),
  Size                  INTEGER         NOT NULL                                                CHECK(Size BETWEEN 1 AND 16777216),
  Width                 INTEGER                                                 DEFAULT NULL,
  Height                INTEGER                                                 DEFAULT NULL,

  CHECK((Width IS NOT NULL AND Height IS NOT NULL) OR (Width IS NULL AND Height IS NULL))
) WITHOUT ROWID;

CREATE TABLE GlobalConfig (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY,
  Value                 NUMERIC         NOT NULL
) WITHOUT ROWID;

CREATE TABLE Accounts (
  Name                  TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Name) BETWEEN 1 AND 16),
  Type                  TEXT            NOT NULL,
  Board                 TEXT,
  PwHash                TEXT            NOT NULL,

  FOREIGN KEY (Board) REFERENCES Boards (Name) ON UPDATE CASCADE ON DELETE CASCADE,
  CHECK((Type IN ('admin', 'gvol') AND Board IS NULL) OR (Type IN ('bo', 'lvol') AND Board IS NOT NULL))
) WITHOUT ROWID;

CREATE TABLE Sessions (
  Key                   TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Key) = 16),
  Account               TEXT            NOT NULL        UNIQUE,
  ExpireDate            DATETIME        NOT NULL                                DEFAULT 0,

  FOREIGN KEY (Account) REFERENCES Accounts (Name) ON UPDATE CASCADE ON DELETE CASCADE
) WITHOUT ROWID;

CREATE TABLE Logs (
  Account               TEXT            NOT NULL                                DEFAULT 'SYSTEM',
  Board                 TEXT            NOT NULL                                DEFAULT 'GLOBAL',
  Date                  DATETIME        NOT NULL                                DEFAULT 0,
  Description           TEXT            NOT NULL                                                CHECK(LENGTH(Description) > 0)
);

CREATE TABLE Captchas (
  Id                    TEXT            NOT NULL        UNIQUE  PRIMARY KEY                     CHECK(LENGTH(Id) = 16),
  Text                  TEXT            NOT NULL                                                CHECK(LENGTH(Text) = 6),
  ExpireDate            DATETIME        NOT NULL                                DEFAULT 0
) WITHOUT ROWID;

CREATE TABLE Webring (
  Endpoint              TEXT            NOT NULL        UNIQUE  PRIMARY KEY,
  Type                  TEXT            NOT NULL                                DEFAULT 'known',
  CHECK(Type IN ('following', 'known', 'blacklist'))
) WITHOUT ROWID;

CREATE TRIGGER bump_thread AFTER INSERT ON Posts
  WHEN NEW.Parent IS NOT NULL AND NEW.Email NOT LIKE '%sage%'
   AND (SELECT ReplyCount FROM Posts WHERE Board = NEW.Board AND Number = NEW.Parent)
       <= (SELECT BumpLimit FROM Boards WHERE Name = NEW.Board)
BEGIN
  UPDATE Posts SET LastBumpDate = STRFTIME('%s', 'now') WHERE Board = NEW.Board AND Number = NEW.Parent AND Autosage = FALSE;
END;

CREATE TRIGGER user_autosage AFTER INSERT ON Posts WHEN NEW.Parent IS NULL AND NEW.Email LIKE '%sage%'
BEGIN
  UPDATE Posts SET Autosage = TRUE WHERE ROWID = NEW.ROWID;
END;

CREATE TRIGGER increment_post_number AFTER INSERT ON Posts
BEGIN
  UPDATE Posts SET Number = (SELECT MaxPostNumber + 1 FROM Boards WHERE Name = NEW.Board) WHERE ROWID = NEW.ROWID;
  UPDATE Boards SET MaxPostNumber = MaxPostNumber + 1 WHERE Name = NEW.Board;
  UPDATE Posts SET ReplyCount = ReplyCount + 1 WHERE NEW.Parent IS NOT NULL AND Board = NEW.Board AND Number = NEW.Parent;
END;

CREATE TRIGGER set_post_date AFTER INSERT ON Posts
BEGIN
  UPDATE Posts SET Date = STRFTIME('%s', 'now'), LastBumpDate = STRFTIME('%s', 'now') WHERE ROWID = NEW.ROWID;
END;

CREATE TRIGGER set_post_replycount AFTER INSERT ON Posts
  WHEN NEW.Parent IS NULL
BEGIN
  UPDATE Posts SET ReplyCount = 0 WHERE ROWID = NEW.ROWID;
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

CREATE TRIGGER delete_cyclical BEFORE INSERT ON Posts
  WHEN (SELECT Cycle FROM Posts WHERE Board = NEW.Board AND Number = NEW.Parent) = TRUE
   AND (SELECT ReplyCount FROM Posts WHERE Board = NEW.Board AND Number = NEW.Parent)
       >= (SELECT PostLimit FROM Boards WHERE Name = NEW.Board)
BEGIN
  DELETE FROM Posts WHERE Board = NEW.Board AND Number = (SELECT MIN(Number) FROM Posts WHERE Parent = NEW.Parent);
END;

CREATE TRIGGER slide_thread BEFORE INSERT ON Posts
  WHEN (SELECT COUNT(*) FROM Posts WHERE Board = NEW.Board AND Parent IS NULL)
       >= (SELECT ThreadLimit FROM Boards WHERE Name = NEW.Board)
   AND NEW.Parent IS NULL
BEGIN
  DELETE FROM Posts
  WHERE Board = NEW.Board AND Parent IS NULL AND Sticky = FALSE
        AND LastBumpDate = (SELECT MIN(LastBumpDate) FROM Posts WHERE Board = NEW.Board AND Parent IS NULL);
END;

CREATE TRIGGER decrement_replycount BEFORE DELETE ON Posts
  WHEN OLD.Parent IS NOT NULL
BEGIN
  UPDATE Posts SET ReplyCount = ReplyCount - 1 WHERE Board = OLD.Board AND Number = OLD.Parent;
END;

CREATE TRIGGER delete_old_sessions BEFORE INSERT ON Sessions
BEGIN
  DELETE FROM Sessions WHERE Account = NEW.Account;
END;

CREATE TRIGGER set_session_expiry AFTER INSERT ON Sessions
BEGIN
  UPDATE Sessions SET ExpireDate = STRFTIME('%s', 'now') + 86400 WHERE Key = NEW.Key;
END;

CREATE TRIGGER set_log_date AFTER INSERT ON Logs
BEGIN
  UPDATE Logs SET Date = STRFTIME('%s', 'now') WHERE ROWID = NEW.ROWID;
END;

CREATE TRIGGER set_captcha_expiry AFTER INSERT ON Captchas
BEGIN
  UPDATE Captchas SET ExpireDate = STRFTIME('%s', 'now') + 1800 WHERE Id = NEW.Id;
END;

CREATE INDEX posts_parent_number ON Posts (Parent, Number);
CREATE INDEX posts_date ON Posts (Date DESC);
CREATE INDEX captchas_expiredate ON Captchas (ExpireDate);
CREATE INDEX boards_displayoverboard ON Boards (DisplayOverboard);

-- This is a default account. You should use this only for setup purposes.
-- The setup account should be DELETED after you make your main admin account.
-- The initial username is 'setup' and the password is 'password'.
INSERT INTO Accounts (Name, Type, PwHash) VALUES ('setup', 'admin', '$argon2id$v=19$m=65536,t=16,p=4$dnFMZDFSRkhMWXFKdGV4TA$B3+O7QbPE/e42Js3sr4ldhtPP4ibRpas1KZquqidMDysu4NdvdX3EA2/X9rdb2LjzB/UDj8dwfKWQxLbcgVZFg');
INSERT INTO GlobalConfig VALUES ('sitename', 'Picochan');
INSERT INTO GlobalConfig VALUES ('defaultpostname', 'Anonymous');
INSERT INTO GlobalConfig VALUES ('frontpage', 'Welcome to Picochan.');
INSERT INTO GlobalConfig VALUES ('theme', 'picochan');
INSERT INTO GlobalConfig VALUES ('indexpagesize', 10);
INSERT INTO GlobalConfig VALUES ('indexwindowsize', 5);
INSERT INTO GlobalConfig VALUES ('recentpagesize', 50);
INSERT INTO GlobalConfig VALUES ('logpagesize', 50);
INSERT INTO GlobalConfig VALUES ('url', 'http://localhost');
