# /update-docs

Automatically analyzes the codebase and updates all documentation files including README.md, CLAUDE.md, and other documentation to reflect current code state and architecture.

## What this command does:

1. **Analyzes Current Codebase**: Scans all source files to understand:
   - Project structure and architecture
   - Available features and functionality
   - Build commands and development workflow
   - Dependencies and configuration

2. **Updates Documentation Files**:
   - `README.md`: User-facing project documentation
   - `CLAUDE.md`: Claude Code specific guidance and architecture notes
   - Any other `.md` files found in the project
   - Inline code documentation where needed

3. **Maintains Consistency**: Ensures all documentation:
   - Reflects current code state
   - Uses consistent terminology
   - Includes accurate build/run instructions
   - Documents new features and changes

4. **Preserves Important Content**: 
   - Keeps existing important content
   - Maintains custom sections marked with preservation tags
   - Updates only outdated or missing information

## Usage:
```
/update-docs
```

## Options:
- Run without arguments to update all documentation
- Automatically detects what needs updating based on git changes
- Preserves user-written content while updating technical details

This command should be run after significant code changes, new feature additions, or architectural updates to keep documentation in sync with the codebase.