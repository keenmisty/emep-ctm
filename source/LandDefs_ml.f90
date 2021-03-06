! <LandDefs_ml.f90 - A component of the EMEP MSC-W Chemical transport Model, version rv4_10(3282)>
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
!><LandDefs_ml.f90 - A component of the EMEP MSC-W  Chemical transport Model>
!*****************************************************************************! 

module LandDefs_ml
 use CheckStop_ml, only : CheckStop, StopAll
 use Io_ml, only : IO_TMP, open_file, ios, Read_Headers, read_line
 use KeyValueTypes, only :  KeyVal
 use LandPFT_ml,  only : PFT_CODES
 use ModelConstants_ml, only : NLANDUSEMAX, MasterProc, DEBUG
 use ModelConstants_ml, only :  FLUX_VEGS
 use SmallUtils_ml, only : find_index, trims
  implicit none
  private

!=============================================================================
! This module reads  inthe basics landuse data features, e.g. defaults
! for heights, LAI, growinf-season, etc.
! The list given below can be changed, extended or reduced, but then other
! input data files and codimg are needed.

!-----------------------------------------------------------------------------
! Notes: Basis was Emberson et al, EMEP Report 6/2000
!
! flux_wheat is an artificial species with constant LAI, SAI, h throughout year,
! to allow Fst calculations without knowing details of growing season.

! Language: F-compliant

  ! 2 ) Phenology part
!**** DESCRIPTION**********************************************************
! reads in or sets phenology data used for the default deposition module
! Users with own phenology data can simply provide their own subroutines
! (replacing Init_phenology and Phenology)
!**************************************************************************

 public  :: Init_LandDefs         ! Sets table for LAI, SAI, hveg
 public  :: Growing_season 
 public  :: Check_LandCoverPresent 

interface Check_LandCoverPresent
  module procedure Check_LandCoverPresent_Item
  module procedure Check_LandCoverPresent_Array
end interface Check_LandCoverPresent

 real, public, parameter :: STUBBLE  = 0.01 ! Veg. ht. out of season
 integer, public, parameter :: NLANDUSE_EMEP=29 !No. of categories defined 
                                                !in EMEP grid (per April 2013)
 integer, public, save :: iLC_grass    ! Used with clover outputs

!******   Data to be read from Phenology_inputs.dat:

  type, public :: land_input
     character(len=20) :: name
     character(len=20) :: code
     character(len=3) :: type   ! Ecocystem type, see headers
     character(len=5) :: LPJtype   ! Simplified LPJ assignment
     real    ::  hveg_max
     real    ::  Albedo
     integer ::  eNH4         ! Possible source of NHx
     integer ::  SGS50        ! Start of grow season at 50 deg. N
     real    ::  DSGS         ! Increase in SGS per degree N
     integer ::  EGS50        ! End of grow season at 50 deg. N
     real    ::  DEGS         ! Increase in EGS per degree N
     real    ::  LAImin       ! Min value of LAI
     real    ::  LAImax       ! Max value of LAI
     integer ::  SLAIlen      ! Length of LAI growth periods
     integer ::  ELAIlen      ! Length of LAI decline periods
     real    ::  BiomassD     ! Dry biomass density g/m2(ground area)
     real    ::  Eiso         ! Emission potential isoprene, ug/g/h
     real    ::  Emtl         ! Emission potential m-terpenes, light
     real    ::  Emtp         ! Emission potential m-terpenes, pool
  end type land_input
                                               !##############
  type(land_input), public, dimension(NLANDUSEMAX) :: LandDefs
                                               !##############
  type(land_input), private :: LandInput

  type, public :: land_type
     logical :: has_lpj ! if LPJ LAI/BVOC data to be used
     integer :: pft    ! for assignment to equivalent PFT
     logical :: is_forest
     logical :: is_conif
     logical :: is_decid
     logical :: is_crop 
     logical :: is_seminat 
     logical :: is_water
     logical :: is_ice
     logical :: is_veg
     logical :: is_bulk  ! Bulk-surface resistance used 
     logical :: is_iam   ! Fake species for IAM outputs 
     logical :: is_clover ! Fake species for clover
     logical :: flux_wanted ! usually IAM, set by My_Derived
  end type land_type
                                               !##############
  type(land_type), public,  dimension(NLANDUSEMAX) :: LandType
                                               !##############
     

contains
!=======================================================================
    subroutine Growing_season(lu,lat,SGS,EGS)
!=======================================================================

!   calculates the start and end of growing season for land-use
!   class "lu" and latitude "lat".  

    integer, intent(in) :: lu         ! Land-use index
    real,    intent(in) :: lat        ! Latitude 
    integer, intent(out) :: SGS, EGS  ! start and end of growing season

      if ( LandDefs(lu)%DSGS > 0 )  then ! calculate

        SGS = int ( 0.5 +  LandDefs(lu)%SGS50 + LandDefs(lu)%DSGS * (lat-50.0) )
        EGS = int ( 0.5 +  LandDefs(lu)%EGS50 + LandDefs(lu)%DEGS * (lat-50.0) )
      else
        SGS = LandDefs(lu)%SGS50
        EGS = LandDefs(lu)%EGS50
      end if

      EGS = min(EGS, 366 )  ! Keeps EGS to 366 to allow for leap year
                            ! (and ignore diff 365/366 otherwise)

  end subroutine Growing_season

  !=======================================================================
  subroutine Init_LandDefs(ncodes, wanted_codes)
  !=======================================================================
      !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Reads file Inputs_LandDefs.csv and extracts land-defs. Checks that
      ! codes match the "wanted_codes" which have been set in Inputs-Landuse
      integer, intent(in) :: ncodes  ! Num. land codes found in mapped data
      character(len=*), dimension(:), intent(in) :: wanted_codes
      character(len=20), dimension(25) :: Headers
      character(len=200) :: txtinput  ! Big enough to contain one input record
      type(KeyVal), dimension(2) :: KeyValues ! Info on units, coords, etc.
      character(len=50) :: errmsg, fname
      character(len=*), parameter :: sub='Ini-LandDefs:'
      integer :: n, nn, NHeaders, NKeys
      logical :: dbg

      dbg = ( DEBUG%LANDDEFS .and. MasterProc ) 

      ! Quick safety check (see Landuse_ml for explanation)
       call CheckStop(&
         maxval( len_trim(wanted_codes(:))) >= len(LandInput%code),& 
          sub//" increase size of character array" )

      ! Read data


      fname = "Inputs_LandDefs.csv"
      if ( MasterProc ) then
         write(*,*) sub//" for Ncodes= ", ncodes
         do n = 1, ncodes
            write(*,*) sub//"LC  wants ",n, trim(wanted_codes(n))
         end do
         call open_file(IO_TMP,"r",fname,needed=.true.)
         call CheckStop(ios,sub//"open_file error on " // fname )
      end if

      call Read_Headers(IO_TMP,errmsg,NHeaders,NKeys,Headers,Keyvalues)

      call CheckStop( errmsg , sub//"Read Headers" )
 

      !------ Read in file. Lines beginning with "!" are taken as
      !       comments and skipped

       nn = 0     
       do
            call read_line(IO_TMP,txtinput,ios)
            if ( ios /= 0 ) then
                 exit   ! likely end of file
            end if
            if ( dbg ) write(*,*) sub//' READLINE: ------ '// trim(txtinput)
            if ( txtinput(1:1) == "#" ) then
                 cycle
            end if
            if ( txtinput(1:2) == '"#' ) then!Common problem after saving .csv!
                 call StopAll(trim(fname)//&
                 ': Quotation mark at start of "# line:'//trim(txtinput) )
            end if
            read(unit=txtinput,fmt=*,iostat=ios) LandInput
            call CheckStop ( ios, fname // " txt error:" // trim(txtinput) )
            n = find_index( LandInput%code, wanted_codes )!index in map data?
            if ( n < 1 ) then
                if ( MasterProc ) write(*,*) sub//" skipping nn,n ",&
                   nn,n, trim(LandInput%code)
                cycle
            end if
           !############################
            LandDefs(n) = LandInput
            nn = nn + 1
           !############################

        !/ Set any input negative values to physical ones (some were set as -1)

           LandDefs(n)%hveg_max = max( LandDefs(n)%hveg_max, 0.0)
           LandDefs(n)%LAImax   = max( LandDefs(n)%LAImax,   0.0)


            if ( dbg ) then
                 write(*,"(a)") trim(txtinput)
                 write(unit=*,fmt="(a,3i3,2a,2i5,f7.3,f10.3)") sub//":=> ", &
                  n,nn, ncodes, trim(LandInput%name), trim(LandInput%code),&
                    LandDefs(n)%SGS50,LandDefs(n)%EGS50, &
                    LandDefs(n)%LAImax, LandDefs(n)%Emtp
            end if
            call CheckStop(  LandInput%code, wanted_codes(n), sub//"MATCHING CODES")

            LandType(n)%is_water  =  LandInput%code == "W" 
            LandType(n)%is_ice    =  LandInput%code == "ICE" 
            LandType(n)%is_iam    =  LandInput%code(1:4) == "IAM_" 
            LandType(n)%is_clover =  LandInput%code(1:2) == "CV" 
            LandType(n)%flux_wanted = LandType(n)%is_iam  ! default
           !Also:
           if( find_index( LandInput%code, FLUX_VEGS(:) ) > 0 ) then
             if(MasterProc) write(*,*) sub//"FLUX_VEG SET:", trim(LandInput%code)
             LandType(n)%flux_wanted = .true.
           end if

            LandType(n)%is_forest =  &
                (  LandDefs(n)%hveg_max > 4.0 .and. &    !  Simpler definition 
                   LandDefs(n)%LAImax > 0.5           )  ! Excludes Urban

            LandType(n)%has_lpj   = ( LandInput%type /= "NOLPJ" )

            LandType(n)%pft = find_index( LandDefs(n)%LPJtype, PFT_CODES)

            if ( dbg ) write(unit=*,fmt='(a,i3,a,i5)') sub//"PFT? ", n,&
             trims(LandInput%name//':'// LandInput%code//':'// &
                   wanted_codes(n) ), LandType(n)%pft

           !is_decid, is_conif used mainly for BVOC and soil-NO. Not essential
           ! for IAM-type landcover
            LandType(n)%is_conif = ( LandInput%type == "ECF"  )
            LandType(n)%is_decid = ( LandInput%type == "EDF"  )
            LandType(n)%is_crop  = ( LandInput%type == "ECR"  )
            LandType(n)%is_seminat  = ( LandInput%type == "SNL"  )
            LandType(n)%is_bulk   =  LandInput%type == "BLK" 
            LandType(n)%is_veg    =  LandInput%code /= "U" .and. &
                  LandInput%hveg_max > 0.01   ! Excludes water, ice_nwp, desert 
            if( LandInput%code(1:2) == "GR" ) iLC_grass =  n ! for use with clover
       end do
       if ( MasterProc ) then 
             close(unit=IO_TMP)
             write(*,*) sub//"DONE NN,NCODES = ", nn, ncodes
       end if

       call CheckStop( nn /= ncodes, sub//" didn't find all codes")

  end subroutine Init_LandDefs
 !=========================================================================
  function Check_LandCoverPresent_Item( descrip, txt, write_condition) result(ind)
    character(len=*),intent(in) :: descrip
    character(len=*),intent(in) :: txt
    logical, intent(in) :: write_condition
    integer :: ind

          if( trim(txt) == "Grid") then  ! Grid is a special case
             ind = 0
          else
             ind = find_index(  txt, LandDefs(:)%code )
          !if( DEBUG ) print *, "LC-CHECKING", descrip, txt, ind
          end if
          if( ind < 0 .and.  write_condition .and. MasterProc ) write(*,*) &
                descrip // "NOT FOUND!! Skipping : " //  txt
  end function Check_LandCoverPresent_Item
 !=========================================================================
  function Check_LandCoverPresent_Array( descrip, n, txt, write_condition) result(ind)
    character(len=*),intent(in) :: descrip
    integer, intent(in) :: n
    character(len=*),dimension(:),intent(in) :: txt
    logical, intent(in) :: write_condition
    integer :: ind

          if( trim(txt(n)) == "Grid") then  ! Grid is a special case
             ind = 0
          else
             ind = find_index(  txt(n), LandDefs(:)%code )
          end if
          !if( DEBUG ) print *, "LC-CHECKING", descrip, n, txt(n), ind
          if( ind < 0 .and.  write_condition .and. MasterProc ) write(*,*) &
                descrip // "NOT FOUND!! Skipping : " //  txt(n)
  end function Check_LandCoverPresent_Array
 !=========================================================================

end module LandDefs_ml
