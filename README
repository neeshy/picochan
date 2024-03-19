Picochan is imageboard software.

Key features which differentiate picochan from mainstream imageboard software
like vichan and friends:

  - No javascript of any type is used anywhere. In fact, CSP is used to block
    execution of any and all javascript, which makes XSS attacks impossible.
    Despite this, many "javascript" features such as floating reply box,
    working mobile view, inline image expansion etc. are present
  - High speed and small code size along with good feature density
  - High security due to the use of pledge() and unveil()
  - Highly transparent moderation logs which include a reason for all
    moderation actions such as deleting a post, autosaging a thread etc.

For reference, this software is loosely based upon nanochan, but most of it
is rewritten. Several key improvements exist in picochan which do not exist in
nanochan:

  - Support for:
    - improved post formatting options
    - multiple files per post
    - uploader provided filenames
    - spoilered images
    - inline image expansion
    - cross-board links where the post linked to is not a thread
    - intra-board links where the post linked to is not in the current thread
    - per-board index and recent pages
    - paginated catalog pages and threads
    - multiple themes
    - more extensive moderation tools
    - more board settings
    - configurable site name
  - Database structure is significantly improved. This increases speed by a
    large amount (orders of magnitude), especially with large boards or long
    threads
  - Backend and frontend are separate. This improves code simplicity a little
    and also allows for more frontends in the future
  - LuaJIT is used, and the software's speed is further improved
  - HTML meta http-equiv tags have been eliminated in favor of HTTP headers
  - Removal of the haserl dependency

Installation instructions can be found at /INSTALL
