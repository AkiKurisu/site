@echo off
call .\env\Scripts\activate.bat
python .\scripts\blog_helper.py  post Hello NewPost --draft
pause