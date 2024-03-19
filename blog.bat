@echo off
call .\env\Scripts\activate.bat
python .\scripts\blog_helper.py  post NewPost NewPost --draft
call .\env\Scripts\deactivate.bat