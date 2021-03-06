! <LandPFT_ml.f90 - A component of the EMEP MSC-W Chemical transport Model, version rv4_10(3282)>
!*****************************************************************************!
!*
!*  Copyright (C) 2007-2016 met.no
!*
!*  Contact information:
!*  Norwegian Meteorological Institute
!*  Box 43 Blindern
!*  0313 OSLO
!*  NORWAY
!*  email: emep.mscw@met.no
!*  http://www.emep.int
!*
!*    This program is free software: you can redistribute it and/or modify
!*    it under the terms of the GNU General Public License as published by
!*    the Free Software Foundation, either version 3 of the License, or
!*    (at your option) any later version.
!*
!*    This program is distributed in the hope that it will be useful,
!*    but WITHOUT ANY WARRANTY; without even the implied warranty of
!*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!*    GNU General Public License for more details.
!*
!*    You should have received a copy of the GNU General Public License
!*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
!*****************************************************************************!
!> <LandPFT_ml.f90 - A component of the EMEP MSC-W Chemical transport Model>
!! *************************************************************************! 
!! Reads LAI maps from Global LPJ-GUESS model
!! Data provided by Guy Schurgers & Almut Arneth (Lund University) 
!! and normalised to LAI factors for EMEP usage (DS)

module LandPFT_ml

use CheckStop_ml,   only: CheckStop, StopAll
use GridValues_ml,  only: debug_proc, debug_li, debug_lj, glon, glat
use ModelConstants_ml,  only : DEBUG, MasterProc, BVOC_USED, PFT_MAPPINGS
use NetCDF_ml, only: ReadField_CDF
use Par_ml,         only: LIMAX, LJMAX, me
use SmallUtils_ml,  only: find_index, NOT_FOUND, WriteArray, trims

implicit none
private


!/- subroutines:

  public :: MapPFT_LAI
  public :: MapPFT_BVOC


 INCLUDE 'mpif.h'
 INTEGER STATUS(MPI_STATUS_SIZE),INFO

 character(len=80), private :: errmsg

 real, public, allocatable :: pft_lai(:,:,:) 
 real, public, allocatable :: pft_bvoc(:,:,:,:) 

 ! PFTs available from smoothed LPJ fields

  integer, public, parameter :: N_PFTS = 6
  character(len=5),public, parameter, dimension(N_PFTS) :: PFT_CODES = &
        (/ "CF   ", "DF   ", "NF   ", "BF   ", "C3PFT", "C4PFT" /) 

   ! Variables available:

    !NORMED character(len=5),public, parameter :: LAI_VAR =  "LAIv_"
    character(len=5),public, parameter :: LAI_VAR =  "LAIv"
    character(len=5),public, parameter, dimension(2) :: BVOC_VAR = &
        (/ "Eiso_" , "Emt_ " /)

   !skip (/ "Normed_LAIv", "LAIv_      ", "Emt_       ", "Eiso_      " /)

contains

 !==========================================================================
 subroutine MapPFT_LAI(month)

!.....................................................................
!**    DESCRIPTION:

!    Reads the processed LPJ-based LAIv and BVOC emission potentials.
!    The LPJ data have been merged into 4 EMEP forest classes and two
!    other veg, for either C3 or C4 vegetation.
!    Normed_LAIv is relative LAI, with max value 1.0


    integer, intent(in) :: month

    real    :: lpj(LIMAX,LJMAX)  ! Emissions read from file
    logical :: my_first_call = .true.
    integer :: pft
    character(len=20) :: varname

!PFT return ! JAN31TEST. This code needs to be  completed still *****
     if ( my_first_call ) then
         allocate ( pft_lai(LIMAX,LJMAX,N_PFTS) )
         my_first_call = .false.
!call Test_LocalBVOC()
!call GetMEGAN_BVOC()

     end if
         
    ! Get LAI data:

     do pft =1, N_PFTS
           varname = trims( "Normed_" // LAI_VAR // PFT_CODES(pft) ) 

           call ReadField_CDF('GLOBAL_LAInBVOC.nc',varname,&
              lpj,month,interpol='zero_order',needed=.true.,debug_flag=.false.)

           pft_lai(:,:,pft ) = lpj(:,:)
           if( DEBUG%PFT_MAPS.gt.0 .and. debug_proc ) then
             write(*,"(a20,2i3,3f8.3)") "PFT_DEBUG "//trim(varname), &
                 month, pft, &
                 glon(debug_li, debug_lj), glat(debug_li, debug_lj), &
                 lpj(debug_li, debug_lj)
           end if

     end do ! pft

  end subroutine MapPFT_LAI

 !==========================================================================

 subroutine MapPFT_BVOC(month)

!.....................................................................
!**    DESCRIPTION:

!    Reads the processed LPJ-based LAIv and BVOC emission potentials.
!    The LPJ data have been merged into 4 EMEP forest classes and two
!    other veg, for either C3 or C4 vegetation.
!    Normed_LAIv is relative LAI, with max value 1.0


    integer, intent(in) :: month

    real    :: lpj(LIMAX,LJMAX)  ! Emissions read from file
    logical :: my_first_call = .true.
    integer ::  pft, ivar
    character(len=20) :: varname

    ! Ebvoc already includes monthly LAI changes - might be wrong?
    
return ! JAN31TEST
     if ( my_first_call ) then
         allocate ( pft_bvoc(LIMAX,LJMAX,N_PFTS,size(BVOC_USED)) )
         my_first_call = .false.
     end if
         
    ! Get BVOC data. Code assumes that we want isoprene first, then
    !    apinene if provided. Multiple terpenes not considered yet,
    !    but we have just Emt anyway.


     do pft =1, N_PFTS
       do ivar =1, size( BVOC_USED ) 
           varname = trim(BVOC_VAR(ivar)) // trim(PFT_CODES(pft)) 

           call ReadField_CDF('GLOBAL_LAInBVOC.nc',varname,&
              lpj,month,interpol='zero_order',needed=.true.,debug_flag=.true.)

           pft_bvoc(:,:,pft, ivar ) = lpj(:,:)

       end do ! ivar
     end do ! pft


 end subroutine MapPFT_BVOC

 !==========================================================================

! subroutine Test_LocalBVOC()
!
!!.....................................................................
!!**    DESCRIPTION:
!
!!    Reads the processed LPJ-based LAIv and BVOC emission potentials.
!!    The LPJ data have been merged into 4 EMEP forest classes and two
!!    other veg, for either C3 or C4 vegetation.
!!    Normed_LAIv is relative LAI, with max value 1.0
!
!
!
!    real    :: loc(LIMAX,LJMAX)  ! Emissions read from file
!    logical :: my_first_call = .true.
!    integer ::  n, pft, ivar, iVeg, iEmis
!    character(len=1000) :: varname
!    character(len=2), dimension(4) :: VegName = (/ "CF", "DF", "NF", "BF" /)
!    character(len=4), dimension(3) :: EmisName = (/ "Eiso", "Emt ", "Emtl" /)
!
!
!       varname = "Fake"
!
!       call ReadField_CDF('LOCAL_BVOC.nc',varname,&
!           loc,1,interpol='zero_order',needed=.true.,debug_flag=.true.)
!
!       if( debug_proc ) print *, "LOCAL_BVOC 0,0", loc(1, 1)
!       if( debug_proc ) print *, "LOCAL_BVOC i,j", loc(debug_li, debug_lj)
!       !print *, "LOCAL_BVOC me,i,j", me, maxval(loc)
!
!     do iVeg = 1, size(VegName)
!     do iEmis = 1, size(EmisName)
!        varname = trim(EmisName(iEmis)) // "_" // trim(VegName(iVeg))
!        call ReadField_CDF('LOCAL_BVOC.nc',varname,&
!           loc,1,interpol='zero_order',needed=.true.,debug_flag=.true.)
!       if( debug_proc ) print "(a,a,f12.3)", "LOCAL_BVOC:E ", trim(varname), loc(debug_li, debug_lj)
!     end do
!     end do
!
!  end subroutine Test_LocalBVOC
!
! !=======================================================================
end module LandPFT_ml
