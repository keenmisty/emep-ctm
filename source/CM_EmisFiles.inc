  integer, parameter, public ::  NEMIS_File  = 7
  character(len=4), save, dimension(NEMIS_File), public:: &
      EMIS_File =  (/ &
             "sox " &
           , "nox " &
           , "co  " &
           , "voc " &
           , "nh3 " &
           , "pm25" &
           , "pmco" &
 /)
 