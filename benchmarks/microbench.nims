when defined(threadSanitizer) or defined(addressSanitizer):
  switch("define", "useMalloc")
  switch("debugger", "native")
  switch("define", "noSignalHandler")

  when defined(windows):
    when defined(addressSanitizer):
      switch("passC", "/fsanitize=address")
    else:
      {.warning: "Thread Sanitizer is not supported on Windows.".}
  else:
    when defined(threadSanitizer):
      switch("passC", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
      switch("passL", "-fsanitize=thread -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer")
    elif defined(addressSanitizer):
      switch("passC", "-fsanitize=address -fno-omit-frame-pointer")
      switch("passL", "-fsanitize=address -fno-omit-frame-pointer")
