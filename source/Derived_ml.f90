! <Derived_ml.f90 - A component of the EMEP MSC-W Chemical transport Model, version rv4_10(3282)>
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
module Derived_ml
!---------------------------------------------------------------------------
! DESCRIPTION
! This module performs the calculations associated with "derived" 2D and 3D,
! such as accumulated precipitation or sulphate, daily, monthly or yearly
! averages, depositions. These fields are all typically output as netCDF
! fields.
!
! This routine defines many possible derived  outputs.
! The names of the derived fields actualy required should have been specified
!  in the user-defined My_Derived_ml.
!
! User-defined routines and treatments are often needed here. Here there is
! added stuff for VOC, AOTs, accsu. In
! general such code should be added in such a way that it isn't activated if
! not needed. It then doesn't need to be commented out if not used.
!---------------------------------------------------------------------------

use My_Derived_ml, only : &
    wanted_deriv2d, wanted_deriv3d, & ! names of wanted derived fields
    Init_My_Deriv, My_DerivFunc,    &
    OutputFields, nOutputFields,    &
    nOutputMisc, OutputMisc,        &
    nOutputWdep, WDEP_WANTED, D3_OTHER

use AOTx_ml,          only: Calc_GridAOTx
use Biogenics_ml,     only: EmisNat, NEMIS_BioNat, EMIS_BioNat
use CheckStop_ml,     only: CheckStop
use Chemfields_ml,    only: xn_adv, xn_shl, cfac,xn_bgn, AOD,  &
                            SurfArea_um2cm3, &
                            Fgas3d, & ! FSOA
                            Extin_coeff, PM25_water, PM25_water_rh50
use Chemfields_ml ,   only: so2nh3_24hr,Grid_snow
use ChemGroups_ml     ! SIA_GROUP, PMCO_GROUP -- use tot indices
use ChemSpecs         ! Use NSPEC_ADV amd any of IXADV_ indices
use DerivedFields_ml, only: MAXDEF_DERIV2D, MAXDEF_DERIV3D, &
                            def_2d, def_3d, f_2d, f_3d, d_2d, d_3d
use EcoSystem_ml,     only: DepEcoSystem, NDEF_ECOSYSTEMS, &
                            EcoSystemFrac,FULL_ECOGRID
use EmisDef_ml,       only: EMIS_FILE, O_DMS, loc_frac
use EmisGet_ml,       only: nrcemis,iqrc2itot
use Emissions_ml,     only: SumSnapEmis, SumSplitEmis
use GridValues_ml,    only: debug_li, debug_lj, debug_proc, A_mid, B_mid, &
                            dA,dB,xm2, GRIDWIDTH_M, GridArea_m2,xm_i,xm_j,glon,glat
use Io_Progs_ml,      only: datewrite
use MetFields_ml,     only: roa,pzpbl,Kz_m2s,th,zen, ustar_nwp, u_ref,&
                            met, derivmet,  & !TEST of targets
                            ws_10m, rh2m, z_bnd, z_mid, u_mid,v_mid,ps, t2_nwp, &
                            SoilWater_deep, SoilWater_uppr, Idirect, Idiffuse
use ModelConstants_ml, only: &
   KMAX_MID,KMAX_BND  & ! =>  z dimension: layer number,level number
  ,NPROC              & ! No. processors
  ,dt_advec           &  
  ,PPBINV             & ! 1.0e9, for conversion of units
  ,PPTINV             & ! 1.0e12, for conversion of units
  ,DEBUG              & ! gives DEBUG%AOT
  ,AERO               & ! for DpgV (was diam) -  aerosol MMD (um)
  ,PT                 &
  ,FORECAST           & ! only dayly (and hourly) output on FORECAST mode
  ,NTDAY              & ! Number of 2D O3 to be saved each day (for SOMO)
  ,num_lev3d,lev3d    & ! 3D levels on 3D output
  ! output types corresponding to instantaneous,year,month,day
  ,IOU_INST,IOU_YEAR,IOU_MON,IOU_DAY,IOU_HOUR,IOU_HOUR_INST,IOU_KEY &
  ,MasterProc,SOURCE_RECEPTOR,DEBUG_COLSRC  &
  ,USE_AOD, USE_OCEAN_DMS, USE_uEMEP, uEMEP,startdate,enddate

use AOD_PM_ml,            only: AOD_init,aod_grp,wavelength,& ! group and 
                                wanted_wlen,wanted_ext3d      ! wavelengths
use MosaicOutputs_ml,     only: nMosaic, MosaicOutput
use NumberConstants,      only: UNDEF_R
use OwnDataTypes_ml,      only: Deriv, print_Deriv_type, &
                                TXTLEN_DERIV,TXTLEN_SHORT,TXTLEN_IND ! type & length of names
use Par_ml,               only: me,                &      ! for print outs
                                limax, ljmax      ! => used x, y area
use PhysicalConstants_ml, only: PI,KAPPA,ATWAIR,GRAV
use Setup_1dfields_ml,    only: Fpart ! for FSOA work
use SmallUtils_ml,        only: find_index, LenArray, NOT_SET_STRING, trims
use TimeDate_ml,          only: day_of_year,daynumber,current_date,&
                                tdif_days
use TimeDate_ExtraUtil_ml,only: to_stamp
use Units_ml,             only: Units_Scale,Group_Units,&
                                to_molec_cm3 ! converts roa [kg/m3] to M [molec/cm3]
implicit none
private

public  :: Init_Derived
public  :: ResetDerived   ! Resets values to zero
public  :: DerivedProds   ! Calculates any production terms
public  :: AddDeriv       ! Adds Deriv type to def_2d, def_3d
public  :: AddNewDeriv    ! Creates & Adds Deriv type to def_2d, def_3d
private :: Define_Derived
public  :: wanted_iou     ! (iotyp, def%iotyp)
private :: Setups
private :: write_debug
private :: write_debugadv

public  :: Derived        ! Calculations of sums, avgs etc.
private :: voc_2dcalc     ! Calculates sum of VOC for 2d fields
private :: voc_3dcalc     ! Calculates sum of VOC for 3d fields
private :: group_calc     ! Calculates sum of groups, e.g. pm25 from group array

logical, private, parameter :: T = .true., F = .false. ! shorthands only
integer, public, save :: num_deriv2d, num_deriv3d
integer, private,save :: Nadded2d = 0, Nadded3d=0 ! No. defined derived

! List of wanted IOUs
integer, parameter :: &
  IOU_MIN=lbound(IOU_KEY,DIM=1), &
  IOU_MAX=ubound(IOU_KEY,DIM=1)
logical, public, save :: &
  iou_list(IOU_MIN:IOU_MAX)=.false.

! The 2-d and 3-d fields use the above as a time-dimension. We define
! LENOUTxD according to how fine resolution we want on output. For 2d
! fields we use daily outputs. For the big 3d fields, monthly output
! is sufficient.

integer, public, parameter :: &
  LENOUT2D = IOU_HOUR,& ! Allows INST..DAY for 2d fields
  LENOUT3D = IOU_HOUR   ! Allows INST..DAY for 3d fields

!will be used for:
!e.g. d_2d( num_deriv2d,LIMAX, LJMAX, LENOUT2D)
! &   d_3d( num_deriv3d,LIMAX, LJMAX, num_lev3d, LENOUT3D )


! save O3 every hour during one day to find running max
real, save  , allocatable , public :: &     ! to be used for SOMO35
  D2_O3_DAY( :,:,:)

! Fraction of NO3_c below 2.5 um (v. crude so far)

real, save, private :: fracPM25 = -999.9

! Counters to keep track of averaging
! Initialise to zero in Init.

integer, public, allocatable, dimension(:,:), save :: nav_2d,nav_3d

!-- some variables for the VOC sum done for ozone models
!   (have no effect in non-ozone models - leave in code)

integer, private, save :: nvoc   ! No. VOCs
integer, private, dimension(NSPEC_ADV), save :: &
         voc_index, &     ! Index of VOC in xn_adv
         voc_carbon       ! Number of C atoms

logical, private, save :: Is3D
logical, private, save :: dbg0   ! = DEBUG%DERIVED .and. MasterProc
logical, private, save :: dbgP   ! = DEBUG%DERIVED .and. debug_proc
character(len=100), private :: errmsg

integer, private :: i,j,k,l,n, ivoc, iou   ! Local loop variables

integer, private, save :: iadv_O3=-999,     & ! Avoid hard codded IXADV_SPCS
  iadv_NO3_C=-999,iadv_EC_C_WOOD=-999,iadv_EC_C_FFUEL=-999,iadv_POM_C_FFUEL=-999

real, private, save ::                      & ! Avoid hard codded molwt
  ug_NO3_C=-999.0,ug_EC_C_WOOD=-999.0,ug_EC_C_FFUEL=-999.0,ug_POM_C_FFUEL=-999.0

contains

!=========================================================================
subroutine Init_Derived()
  integer :: alloc_err
  dbg0 = (DEBUG%DERIVED .and. MasterProc ) 

  allocate(D2_O3_DAY( LIMAX, LJMAX, NTDAY))
  D2_O3_DAY = 0.0

  if(dbg0) write(*,*) "INIT My DERIVED STUFF"
  call Init_My_Deriv()  !-> wanted_deriv2d, wanted_deriv3d

  ! get lengths of wanted arrays (excludes notset values)
  num_deriv2d = LenArray(wanted_deriv2d,NOT_SET_STRING)
  num_deriv3d = LenArray(wanted_deriv3d,NOT_SET_STRING)

  call CheckStop(num_deriv2d<1,"num_deriv2d<1 !!")

  if(num_deriv2d > 0) then
    if(dbg0) write(*,*) "Allocate arrays for 2d:", num_deriv2d
    allocate(f_2d(num_deriv2d),stat=alloc_err)
    call CheckStop(alloc_err,"Allocation of f_2d")
    allocate(d_2d(num_deriv2d,LIMAX,LJMAX,LENOUT2D),stat=alloc_err)
    call CheckStop(alloc_err,"Allocation of d_2d")
    call CheckStop(alloc_err,"Allocation of d_3d")
    allocate(nav_2d(num_deriv2d,LENOUT2D),stat=alloc_err)
    call CheckStop(alloc_err,"Allocation of nav_2d")
    nav_2d = 0
  endif
  if(num_deriv3d > 0) then
    if(dbg0) write(*,*) "Allocate arrays for 3d: ", num_deriv3d
    allocate(f_3d(num_deriv3d),stat=alloc_err)
    call CheckStop(alloc_err,"Allocation of f_3d")
    allocate(d_3d(num_deriv3d,LIMAX,LJMAX,num_lev3d,LENOUT3D),&
            stat=alloc_err)
    allocate(nav_3d(num_deriv3d,LENOUT3D),stat=alloc_err)
    call CheckStop(alloc_err,"Allocation of nav_3d")
    nav_3d = 0
  endif

  ! Avoid hard codded IXADV_SPCS
  iadv_O3         =find_index('O3'         ,species_adv(:)%name )
  iadv_NO3_C      =find_index('NO3_C'      ,species_adv(:)%name )
  iadv_EC_C_WOOD  =find_index('EC_C_WOOD'  ,species_adv(:)%name )
  iadv_EC_C_FFUEL =find_index('EC_C_FFUEL' ,species_adv(:)%name )
  iadv_POM_C_FFUEL=find_index('POM_C_FFUEL',species_adv(:)%name )

  ! units scaling
  ! e.g. ug_NO3_C = 1.0+e9 * MW(NO3)/MW(air)
  if(iadv_NO3_C      >0)call Units_Scale('ug',iadv_NO3_C      ,ug_NO3_C      )
  if(iadv_EC_C_WOOD  >0)call Units_Scale('ug',iadv_EC_C_WOOD  ,ug_EC_C_WOOD  )
  if(iadv_EC_C_FFUEL >0)call Units_Scale('ug',iadv_EC_C_FFUEL ,ug_EC_C_FFUEL )
  if(iadv_POM_C_FFUEL>0)call Units_Scale('ug',iadv_POM_C_FFUEL,ug_POM_C_FFUEL)

  call Define_Derived()
  call Setups()  ! just for VOC now

  select case(nint(AERO%DpgV(2)*1e7))
    case(25);fracPM25=0.37
    case(30);fracPM25=0.27
  endselect
  if(dbg0) write(*,"(a,2g12.3,i4)") ' CFAC INIT PMFRACTION ', &
      fracPM25, AERO%DpgV(2), nint(1.0e7*AERO%DpgV(2))
  call CheckStop( fracPM25 < 0.01, "NEED TO SET FRACPM25")
endsubroutine Init_Derived
!=========================================================================
subroutine AddNewDeriv( name,class,subclass,txt,unit,index,f2d,&
       dt_scale,scale, avg,iotype,Is3D)
  character(len=*), intent(in) :: name    ! e.g. DDEP_SO2_m2Conif
  character(len=*), intent(in) :: class   ! Type of data, e.g. ADV or VOC
  character(len=*), intent(in) :: subclass
  character(len=*), intent(in) :: txt     ! text where needed, e.g. "Conif"
  character(len=*), intent(in) :: unit    ! writen in netCDF output
  integer, intent(in)  :: index    ! index in concentation array, or other
  integer, intent(in) :: f2d       ! index in f_2d arrays
  logical, intent(in) :: dt_scale  !  where scaling by dt_advec needed,
  real, intent(in)    :: scale     !  e.g. use 100.0 to get cm/s
  logical, intent(in)  :: avg      ! True => average data (divide by
                     ! nav at end),  else accumulate over run period
  character(len=*), intent(in) :: iotype  ! sets daily, monthly, etc.

  logical, intent(in), optional :: Is3D
  type(Deriv) :: inderiv

  if(trim(name)=="HMIX".and.DEBUG%DERIVED .and. MasterProc)&
     write(*,*) "ADDNEWDERIVE", iotype

  inderiv=Deriv(trim(name),trim(class),trim(subclass),&
                trim(txt),trim(unit),index,f2d,dt_scale, scale,&
                avg,iotype)

  call AddDeriv(inderiv,Is3D=Is3D)
endsubroutine AddNewDeriv
!=========================================================================
subroutine AddDeriv(inderiv,Is3D)
  type(Deriv), intent(in) :: inderiv
  logical, intent(in), optional :: Is3D
  logical :: Is3D_local

  dbg0 = (DEBUG%DERIVED .and. MasterProc ) 
  Is3D_local = .false.
  if(present(Is3D)) Is3D_local = Is3D

  if(Is3D_local) then
    Nadded3d = Nadded3d + 1
    N = Nadded3d
    if(dbg0) write(*,*) "Define 3d deriv ", N, trim(inderiv%name)
    call CheckStop(N>MAXDEF_DERIV3D,"Nadded3d too big!")
    def_3d(N) = inderiv
  else
    Nadded2d = Nadded2d + 1
    N = Nadded2d
    if(dbg0)then
      write(*,"(a,i6)") "DEBUG AddDeriv 2d ", N
      call print_Deriv_type(inderiv)
    endif
   !if(dbg0) write(*,*) "DALL", inderiv
    call CheckStop(N>MAXDEF_DERIV2D,"Nadded2d too big!")
    def_2d(N) = inderiv
  endif
endsubroutine AddDeriv
!=========================================================================
subroutine Define_Derived()
! Set the parameters for the derived parameters, including the codes
! used by MET.NO/xfelt and scaling factors. (The scaling factors may
! be changed later in Derived_ml.
! And, Initialise the fields to zero.

  real    :: unitscale
  logical :: volunit,semivol  ! set true for volume units (e.g. ppb),group with semivol
  !FAILED logical :: outmm, outdd  ! sets time-intervals

  character(len=30) :: dname, class
  character(len=10) :: unittxt
  character(len=TXTLEN_SHORT) :: outname, outunit, outtyp, outdim, subclass
  character(len=11), parameter:: sub="DefDerived:"
  character(len=TXTLEN_IND)  :: outind

  integer :: ind, iadv, ishl, idebug, n, igrp, iout

  if(dbg0) write(6,*) " START DEFINE DERIVED "
  !   same mol.wt assumed for PPM25 and PPMCOARSE


!-- Deposition fields. Define all possible fields and their xfelt codes here:

      !code class  avg? ind scale rho Inst Yr Mn Day   name      unit

  Is3D = .false.


! We process the various combinations of gas-species and ecosystem:
! stuff from My_Derived

  !Deriv(name, class,    subc,  txt,           unit
  !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw
  ! for AOT we can use index for the threshold, usually 40
  call AddNewDeriv( "AOT40_Grid", "GRIDAOT","subclass","-", "ppb h", &
          40, -99, T, 1.0/3600.0, F,   'YMD'    )
!-------------------------------------------------------------------------------
  !Deriv(name, class,    subc,  txt,           unit
  !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw

! NOT YET: Scale pressure by 0.01 to get hPa
  call AddNewDeriv( "PSURF ","PSURF",  "SURF","-",   "hPa", &
               -99,  -99,  F,  1.0,  T,   'YMD' )

  !Added for TFMM scale runs
  call AddNewDeriv( "Kz_m2s","Kz_m2s",  "-","-",   "m2/s", &
               -99,  -99, F, 1.0,  T,  'YMD' )

  call AddNewDeriv( "u_ref","u_ref",  "-","-",   "m/s", &
               -99,  -99, F, 1.0,  T,  'YMD' )

! call AddNewDeriv( "SoilWater_deep","SoilWater_deep",  "-","-",   "m", &
!               -99,  -99, F, 1.0,  T,  'YMD' )
! call AddNewDeriv( "SoilWater_uppr","SoilWater_uppr",  "-","-",   "m", &
!               -99,  -99, F, 1.0,  T,  'YMD' )

  call AddNewDeriv( "T2m","T2m",  "-","-",   "deg. C", &
               -99,  -99, F, 1.0,  T,  'YMD' )
  call AddNewDeriv( "Idirect","Idirect",  "-","-",   "W/m2", &
               -99,  -99, F, 1.0,  T,  'YMD' )
  call AddNewDeriv( "Idiffuse","Idiffuse",  "-","-",   "W/m2", &
               -99,  -99, F, 1.0,  T,  'YMD' )

! OutputFields can contain both 2d and 3d specs.
! Settings for 2D and 3D are independant.

  do ind = 1, nOutputFields
    outname= trim(OutputFields(ind)%txt1)
    outunit= trim(OutputFields(ind)%txt2)   ! eg ugN, which gives unitstxt ugN/m3
    outdim = trim(OutputFields(ind)%txt3)   ! 2d or 3d or e.g. k20
    outtyp = trim(OutputFields(ind)%txt5)   ! SPEC or GROUP or MISC
    outind = OutputFields(ind)%ind    !  H, D, M - fequency of output
    subclass = '-' ! default
    Is3D = .false.

    if(outtyp=="MISC") then ! Simple species
      iout  = -99 ! find_index( wanted_deriv2d(i), def_2d(:)%name )
      class = trim(OutputFields(ind)%txt4)
      select case(class)
      case ('Z_MID','Z','Z_BND','Zlev','dZ_BND','dZ')
        iadv = -1 
        unittxt="m"
        Is3D=.true.
      case('PM25','PM25X','PM25_rh50','PM25X_rh50','PM10_rh50',&
           'PM25water','PM25_wet','PM10_wet')
        iadv = -1 ! Units_Scale(iadv=-1) returns 1.0
                  ! group_calc gets the unit conversion factor from Group_Units
        call Units_Scale(outunit,iadv,unitscale,unittxt)
        Is3D=(outdim=='3d')
      ! if(MasterProc) write(*,*)"FRACTION UNITSCALE ", unitscale
      case('FLYmax6h','FLYmax6h:SPEC')   ! Fly Level, 6 hourly maximum
        iout=find_index(outname, species_adv(:)%name )
  !-- Volcanic Emission: Skipp if not found
        if(outname(1:3)=="ASH")then
          if(MasterProc.and.DEBUG_COLSRC)&
            write(*,"(A,':',A,1X,I0,':',A)")'ColumSource',trim(outtyp),iadv,trim(outname)
          if(iout<1)cycle
        endif
        call CheckStop(iout<0,sub//"OutputFields "//trim(outtyp)//&
                              " not found "//trim(outname))
        outtyp = "FLYmax6h:SPEC"
        subclass = outdim   ! flxx-yy: xx to yy 1000 feet
        outname = "MAX6h_"//trim(outname)//"_"//trim(subclass)
      case('FLYmax6h:GROUP')          ! Fly Level, 6 hourly maximum
        iout=find_index(outname,chemgroups(:)%name)
  !-- Volcanic Emission: Skipp if not found
        if(outname(1:3)=="ASH")then
          if(MasterProc.and.DEBUG_COLSRC)&
            write(*,"(A,':',A,1X,I0,':',A)")'ColumSource',trim(class),igrp,trim(outname)
          if(iout<1)cycle
        endif
        call CheckStop(iout<0,sub//"OutputFields "//trim(outtyp)//&
                              " not found "//trim(outname))
        outtyp = "FLYmax6h:GROUP"
        subclass = outdim   ! flxx-yy: xx to yy 1000 feet
        outname = "MAX6h_"//trim(outname)//"_"//trim(subclass)
      case('COLUMN','COLUMN:SPEC')
     !COL  'NO2',          'molec/cm2' ,'k20','COLUMN'   ,'MISC' ,4,
        iout=find_index(outname, species_adv(:)%name )
        call CheckStop(iout<0,sub//"OutputFields "//trim(outtyp)//&
                              " not found "//trim(outname))
        call Units_Scale(outunit,iout,unitscale,unittxt)
        outtyp = "COLUMN:SPEC"
        subclass = outdim   ! k20, k16...
        outname = "COLUMN_" // trim(outname) // "_" // trim(subclass)
      case('COLUMN:GROUP')
        iout=find_index(outname,chemgroups(:)%name)
        call CheckStop(iout<0,sub//"OutputFields "//trim(outtyp)//&
                              " not found "//trim(outname))
        call Units_Scale(outunit,-1,unitscale,unittxt)
        outtyp = "COLUMN:GROUP"
        subclass = outdim   ! k20, k16...
        outname = "COLUMN_" // trim(outname) // "_" // trim(subclass)
      case('AOD','AOD:TOTAL','AOD:SPEC','AOD:SHL','AOD:GROUP',&
           'EXT','EXT:TOTAL','EXT:SPEC','EXT:SHL','EXT:GROUP')
        if(.not.USE_AOD)cycle
        select case(class)
        case('AOD:GROUP','EXT:GROUP')
          iout=find_index(outname,chemgroups(:)%name)
          if(outname=="EXT")&
            iout=find_index("AOD",chemgroups(:)%name)
        case('AOD:SPEC' ,'EXT:SPEC' )
          iout=find_index(outname,species_adv(:)%name)
        case default
          call CheckStop(sub//"OutputFields%class  Unsupported "//&
            trim(outtyp)//":"//trim(outname)//":"//trim(outdim))
        endselect
        call CheckStop(iout<0,sub//"OutputFields%class "//trim(class)//&
                              " not found "//trim(outname))
        unitscale = 1.0
        unittxt   = trim(outunit)
        subclass  = outdim   ! 330nm .. 1020nm
        if(outname(1:3)/=class(1:3))&
          outname = class(1:3)//"_"//trim(outname)
        outname   = trim(outname)//"_"//trim(subclass)
        Is3D      = (class(1:3)=="EXT")       
        call AOD_init("Derived:"//trim(class),wlen=trim(subclass),out3d=Is3D)
      case default
         if(outdim=='3d')Is3D=.true.
         unitscale = 1.0
         if(outunit=="ppb") unitscale = PPBINV
         unittxt=trim(outunit)
      endselect

      if(MasterProc)write(*,"(3a)") &
        "Deriv:MISC "//trim(outname),outind,trim(class)

      call AddNewDeriv(outname,class,subclass,"-",trim(unittxt),&
                       iout,-99,F,unitscale,T,outind,Is3D=Is3D)

    else ! SPEC and GROUPS of specs.

      select case(outtyp)
      case("SPEC")  ! Simple species
        iadv = find_index(outname, species_adv(:)%name )
  !-- Volcanic Emission: Skipp if not found
        if(outname(1:3)=="ASH")then
          if(MasterProc.and.DEBUG_COLSRC)&
            write(*,"(A,':',A,1X,I0,':',A)")'ColumSource',trim(outtyp),iadv,trim(outname)
          if(iadv<1)cycle
        endif
        call CheckStop(iadv<0,sub//"OutputFields Species not found "//trim(outname))
        iout = iadv
        call Units_Scale(outunit,iadv,unitscale,unittxt,volunit)
      case("SHL")
        ishl = find_index(outname,species_shl(:)%name)
        call CheckStop(ishl<0,sub//"OutputFields Short lived Species not found "//trim(outname))
        if(MasterProc) &
          write(*,*)"OutputFields Short lived Species found: "//trim(outname)
        iout = ishl
        unitscale = 1.0
        unittxt = "molec/cm3" ! No PPB possibility here !!!
        volunit = .true.
      case("GROUP") ! groups of species
        igrp = find_index(outname, chemgroups(:)%name )
  !-- Volcanic Emission: Skipp if not found
        if(outname(1:3)=="ASH")then
          if(MasterProc.and.DEBUG_COLSRC)&
            write(*,"(A,':',A,1X,I0,':',A)")'ColumSource',trim(outtyp),iadv,trim(outname)
          if(igrp<1)cycle
        endif
        call CheckStop(igrp<0,sub//"OutputFields Group not found "//trim(outname))
        iout = igrp
        call Units_Scale(outunit,-1,unitscale,unittxt,volunit,semivol=semivol)
        ! Units_Scale(iadv=-1) returns 1.0
        ! group_calc gets the unit conversion factor from Group_Units
        if( semivol ) subclass = 'FSOA'    
        if(debug_proc.and.DEBUG%DERIVED) write(*,"(2a)") 'FSOA GRPOM:', &
          trims( outname // ':' // outunit // ':' // subclass )
      case default
        call CheckStop(sub//" Unsupported OutputFields%outtyp "//&
          trim(outtyp)//":"//trim(outname)//":"//trim(outdim))
      endselect

      class="MASS";if(volunit)class="PPB"   ! CHANGE PPB to VOL
      select case(outdim)
      case("2d","2D","SURF")
        Is3D = .false.
        class = "SURF_"//trim(class)  //"_"//trim(outtyp)
        dname = "SURF_"//trim(outunit)//"_"//trim(outname)
        call CheckStop(find_index(dname,def_2d(:)%name)>0,&
          sub//"OutputFields already defined output "//trim(dname))

        if(dbg0) write(*,"(a,2i4,4(1x,a),es10.2)")"ADD",&
          ind, iout, trim(dname),";", trim(class), outind,unitscale
        
      case("3d","3D","MLEV")
        Is3D = .true.
        class = "3D_"//trim(class)  //"_"//trim(outtyp)
        dname = "D3_"//trim(outunit)//"_"//trim(outname)
        call CheckStop(find_index(dname,def_3d(:)%name)>0,&
          sub//"OutputFields already defined output "//trim(dname))

        ! Always print out 3D info. Good to help avoid using 3d unless really needed!
        if( MasterProc ) write(*,"(a,2i4,4(1x,a),es10.2)")"ADD 3D outputs",  &
          ind, iout, trim(dname),";", trim(class), outind,unitscale
      case default
        call CheckStop(sub//" Unsupported OutputFields%outdim "//&
          trim(outtyp)//":"//trim(outname)//":"//trim(outdim))
      endselect
!FSOA call AddNewDeriv(dname,class,"-","-",trim(unittxt),&
      call AddNewDeriv(dname,class,subclass,"-",trim(unittxt),&
                       iout,-99,F,unitscale,T,outind,Is3D=Is3D)
    endif
  enddo ! OutputFields

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  do n = 1, nOutputMisc
    Is3D=(OutputMisc(n)%class=="MET3D").or.(OutputMisc(n)%name(1:2)=='D3')
    if(MasterProc) write(*,"(3(A,1X),L1)") &
      'ADDMISC',trim(OutputMisc(n)%name),'Is3D',Is3D
    call AddDeriv(OutputMisc(n),Is3D=Is3D)
  enddo

!-------------------------------------------------------------------------------
  do n = 1, nMosaic
    if ( dbg0 ) write(*,*) "DEBUG MOSAIC AddDeriv ", n, MosaicOutput(n)
    call AddDeriv( MosaicOutput(n) )
  end do
!-------------------------------------------------------------------------------
! Areas of deposition-related ecosystems. Set externally
  do n = 1, NDEF_ECOSYSTEMS
     if(dbg0) write(*,*) "ECODEF ",n, trim( DepEcoSystem(n)%name )
     call AddDeriv( DepEcoSystem(n) )
  end do
!!-------------------------------------------------------------------------------
!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  do ind = 1, size(WDEP_WANTED(1:nOutputWdep)%txt1)
    dname = "WDEP_"//trim(WDEP_WANTED(ind)%txt1)
    select case(WDEP_WANTED(ind)%txt2)
    case("PREC")
      call AddNewDeriv("WDEP_PREC","PREC ","-","-", "mm",  &
                        -1, -99,   F,    1.0,   F,    'YMD' )
    case("SPEC")
      iadv = find_index(WDEP_WANTED(ind)%txt1, species_adv(:)%name)
      call CheckStop(iadv<1, "WDEP_WANTED Species not found " // trim(dname) )

      call Units_Scale(WDEP_WANTED(ind)%txt3,iadv,unitscale,unittxt)
      call AddNewDeriv( dname, "WDEP", "-", "-", unittxt , &
              iadv, -99,   F, unitscale,     F,  'YMD')
    case("GROUP")
      igrp = find_index(dname, chemgroups(:)%name)
      call CheckStop(igrp<1, "WDEP_WANTED Group not found " // trim(dname) )

      ! Just get units text here.
      ! Init_WetDep gets the unit conversion factors from Group_Scale.
      call Units_Scale(WDEP_WANTED(ind)%txt3,-1,unitscale,unittxt)
      call AddNewDeriv( dname,  "WDEP ","-","-", unittxt ,  &
              igrp, -99,   F,      1.0,   F,    'YMD')
    case default
      call CheckStop("Unknown WDEP_WANTED type " // trim(WDEP_WANTED(ind)%txt2) )
    endselect
    if(MasterProc) write(*,*)"Wet deposition output: ",trim(dname)," ",trim(unittxt)
  enddo

!Emissions:
! We use mg/m2 outputs for consistency with depositions
! Would need to multiply by GridArea_m2 later to get ktonne/grid, but not
! done here.
!
! BVOC called every dt_advec, so use dt_scale=1.0e6 to get from kg/m2/s to
!  mg/m2 accumulated (after multiplication by dt_advec)

    ! AddNewDeriv( name,class,subclass,txt,unit,
    !    index,f2d, dt_scale,scale, avg,iotype,Is3D)

  do  ind = 1, NEMIS_BioNat
    if(EMIS_BioNat(ind)(1:5)=="ASH_L")cycle   ! skip ASH_LxxByy for AshInversion
    dname = "Emis_mgm2_BioNat" // trim(EMIS_BioNat(ind) )
    call AddNewDeriv( dname, "NatEmis", "-", "-", "mg/m2", &
                 ind , -99, T ,    1.0e6,     F, 'YMD' )
  enddo

! SNAP emissions called every hour, given in kg/m2/s, but added to
! d_2d every advection step, so get kg/m2.
! Need 1.0e6 to get from kg/m2 to mg/m2 accumulated.
!
! Future option - might make use of Emis_Molwt to get mg(N)/m2
  do  ind = 1, size(EMIS_FILE)
    dname = "Emis_mgm2_" // trim(EMIS_FILE(ind))
    call AddNewDeriv( dname, "SnapEmis", "-", "-", "mg/m2", &
                       ind , -99, T,  1.0e6,  F,  'YMD' )
  enddo ! ind
  if(USE_OCEAN_DMS)then
    dname = "Emis_mgm2_DMS"
    call AddNewDeriv( dname, "Emis_mgm2_DMS", "-", "-", "mg/m2", &
                       ind , -99, T,  1.0,  F,  'YMD' )
  endif
  if(USE_uEMEP)then
    dname = "Local_Pollutant"
    call AddNewDeriv( dname, "Local_Pollutant", "-", "-", "mg/m2", &
                       -99 , -99, F,  1.0,  T,  'YMD' )
    dname = "Total_Pollutant"
    call AddNewDeriv( dname, "Total_Pollutant", "-", "-", "mg/m2", &
                       -99 , -99, F,  1.0,  T,  'YMD' )
    dname = "Local_Fraction"!NB must be AFTER "Local_Pollutant" and "Total_Pollutant"
    call AddNewDeriv( dname, "Local_Fraction", "-", "-", "", &
                       -99 , -99, F,  1.0,  F,  'YMD' )
    dname = "Local_Pollutant3D"
    call AddNewDeriv( dname, "Local_Pollutant3D", "-", "-", "mg/m2", &
                       -99 , -99, F,  1.0,  T,  'YM' , .true.)
    dname = "Total_Pollutant3D"
    call AddNewDeriv( dname, "Total_Pollutant3D", "-", "-", "mg/m2", &
                       -99 , -99, F,  1.0,  T,  'YM' , .true.)
    dname = "Local_Fraction3D"!NB must be AFTER "Local_Pollutant" and "Total_Pollutant"
    call AddNewDeriv( dname, "Local_Fraction3D", "-", "-", "", &
                       -99 , -99, F,  1.0,  F,  'YM', .true.)
   endif
!Splitted total emissions (inclusive Natural)
  do ind=1,nrcemis
    dname = "EmisSplit_mgm2_"//trim(species(iqrc2itot(ind))%name)
    call AddNewDeriv(dname, "EmisSplit_mgm2", "-", "-", "mg/m2", &
                        ind , -99, T, 1.0e6,   F,  'YMD' )
  enddo

  if(find_index("SURF_PM25water",def_2d(:)%name)<1)&
  call AddNewDeriv("SURF_PM25water", "PM25water", "-", "-","ug/m3", &
                       -99 , -99, F, 1.0,   T,  'YMD' )
! call AddNewDeriv("SURF_PM25", "PM25", "-", "-", "-", &
!                      -99 , -99, F, 1.0,   T,  'YMD' )


! As for GRIDAOT, we can use index for the threshold
  call AddNewDeriv( "SOMO35","SOMO",  "SURF","-",   "ppb.day", &
                  35, -99, F, 1.0,   F,   'YM' )
  call AddNewDeriv( "SOMO0 ","SOMO",  "SURF","-",   "ppb.day", &
                  0 , -99, F, 1.0,   F,   'YM' )
  if(iadv_o3>0) &
  call AddNewDeriv( "SURF_MAXO3","MAXADV", "O3","-",   "ppb", &
           iadv_o3, -99, F, PPBINV,   F,   'YMD')

!-- 3-D fields

Is3D = .true.
  do ind = 1, size(D3_OTHER)
    select case ( trim(D3_OTHER(ind)) )
    case ("D3_PM25water")
      if(find_index("D3_PM25water",def_3d(:)%name)<1)&
      call AddNewDeriv("D3_PM25water", "PM25water", "-", "-","ug/m3", &
         -99, -99, F, 1.0,   T,  'YM',    Is3D ) !

    case ("D3_m_TH")
      call AddNewDeriv("D3_m_TH","TH", "-","-",   "m", &
         -99, -99, F,  1.0,  F,  'YM',     Is3D )

    case ("D3_m2s_Kz")
      call AddNewDeriv( "D3_Kz","Kz", "-","-",   "-", &
         -99, -99, F,  1.0,  F,  'YM',     Is3D )

    case ("D3_T")
      call AddNewDeriv("D3_T","T", "-","-",   "K", &
         -99, -99, F,  1.0,  T,  'YM',     Is3D )

    case ("D3_Zmid")
      if(find_index("D3_Zmid",def_3d(:)%name)<1)&
      call AddNewDeriv("D3_Zmid", "Z_MID", "-", "-", "m", &
                      -99 , -99, F, 1.0,   T, 'YMD',    Is3D  )

     case ("D3_Zlev")
      if(find_index("D3_Zlev",def_3d(:)%name)<1)&
      call AddNewDeriv("D3_Zlev", "Z_BND", "-", "-", "m", &
           -99 , -99, F, 1.0,   T, 'YMD',    Is3D  )
      
     case ("wind_speed_3D")
      call AddNewDeriv("wind_speed_3D", "wind_speed_3D", "-", "-", "m", &
                      -99 , -99, F, 1.0,   T, 'YM',    Is3D  )
    endselect
  enddo

  ! Get indices of wanted fields in larger def_xx arrays:
  do i = 1, num_deriv2d
    if(dbg0) print *,"CHECK 2d", num_deriv2d, i, trim(wanted_deriv2d(i))
    if(MasterProc)&
      call CheckStop(count(f_2d(:i)%name==wanted_deriv2d(i))>0,&
        sub//"REQUESTED 2D DERIVED ALREADY DEFINED: "//trim(wanted_deriv2d(i)))
    ind = find_index( wanted_deriv2d(i), def_2d(:)%name )
    if(ind>0)then
      f_2d(i) = def_2d(ind)
      if(dbg0) print "(2(a,i4),3(1x,a))","Index f_2d ",i,  &
        " = def ",ind,trim(def_2d(ind)%name),trim(def_2d(ind)%unit),trim(def_2d(ind)%class)
    elseif(MasterProc)then
      print *,"D2IND OOOPS wanted_deriv2d not found: ", wanted_deriv2d(i)
      print *,"OOOPS N,N :", num_deriv2d, Nadded2d
      print "(a,i4,a)",("Had def_2d: ",idebug,&
        trim(def_2d(idebug)%name),idebug = 1, Nadded2d)
      call CheckStop(sub//"OOPS STOPPED" // trim( wanted_deriv2d(i) ) )
    endif
  enddo

  do i = 1, num_deriv3d
    if(dbg0) print *,"CHECK 3d", num_deriv3d, i, trim(wanted_deriv3d(i))
    if(MasterProc)&
      call CheckStop(count(f_3d(:i)%name==wanted_deriv3d(i))>0,&
        sub//"REQUESTED 3D DERIVED ALREADY DEFINED: "//trim(wanted_deriv3d(i)))
    ind = find_index( wanted_deriv3d(i), def_3d(:)%name )
    if(ind>0)then
      f_3d(i) = def_3d(ind)
      if(dbg0) print "(2(a,i4),3(1x,a))","Index f_3d ",i,  &
        " = def ",ind,trim(def_3d(ind)%name),trim(def_3d(ind)%unit),trim(def_3d(ind)%class)
    elseif(MasterProc)then
      print *,"D3IND OOOPS wanted_deriv3d not found: ", wanted_deriv3d(i)
      print *,"OOOPS N,N :", num_deriv3d, Nadded3d
      print "(a,i4,a)",("Had def_3d: ",idebug,&
        trim(def_3d(idebug)%name),idebug = 1, Nadded3d)
      call CheckStop(sub//"OOPS STOPPED" // trim( wanted_deriv3d(i) ) )
    endif
  enddo

  !Initialise to zero
  if (num_deriv2d > 0) d_2d(:,:,:,:) = 0.0
  if (num_deriv3d > 0) d_3d(:,:,:,:,:) = 0.0

  dbgP = ( DEBUG%DERIVED  .and. debug_proc )

  ! Determine actual output time ranges for Wanted output
  iou_list(:)=.false.
  do iou=IOU_MIN,IOU_MAX
    do i=1,num_deriv2d
      if(iou_list(iou))exit
      iou_list(iou)=(index(f_2d(i)%iotype,IOU_KEY(iou))>0)
    enddo
    do i=1,num_deriv3d
      if(iou_list(iou))exit
      iou_list(iou)=(index(f_3d(i)%iotype,IOU_KEY(iou))>0)
    enddo
  enddo

  if(SOURCE_RECEPTOR)&            ! We include daily and monthly also 
    iou_list(IOU_DAY+1:)=.false.  ! for SOURCE_RECEPTOR mode which makes
                                  ! it easy for debugging

  if(FORECAST)then                ! reduce output on FORECAST mode
    select case(nint(tdif_days(to_stamp(startdate),to_stamp(enddate))))
      case(   : 27);iou_list(:IOU_DAY-1)=.false. ! Only dayly & hourly outputs
      case( 28:180);iou_list(:IOU_MON-1)=.false. ! .. and monthly
      case(181:   );                             ! .. and full-run
    endselect
  endif

  if(dbgP) write(*,"(A,': ',10(I2,A2,L2,:,','))")"Wanted IOUs",&
    (iou,IOU_KEY(iou),iou_list(iou),iou=IOU_MIN,IOU_MAX)
endsubroutine Define_Derived
!=========================================================================
function wanted_iou(iou,iotype,only_iou) result(wanted)
  integer, intent(in)                 :: iou
  character(len=*),intent(in),optional:: iotype
  integer         ,intent(in),optional:: only_iou
  logical                             :: wanted
  wanted=(iou>=IOU_MIN).and.(iou<=IOU_MAX)  ! in range ov valid IOUs?
  if(wanted)wanted=iou_list(iou)       ! any output requires iou?
  if(wanted.and.present(iotype))then
    wanted=(index(iotype,IOU_KEY(iou))>0)   ! iotype contains IOU_KEY(iou)?
  endif
  if(wanted.and.present(only_iou))then
    wanted=(iou==only_iou)                  ! is only_iou?
  endif
endfunction wanted_iou
!=========================================================================
subroutine Setups()
  integer :: n
  !*** flexibility note. By making use of character-based tests such
  !    as for "VOC" below, we achieve code which can stay for
  !    different chemical mechanisms, without having to define non-used indices.

  !*** if voc wanted, set up voc_array. Works for all ozone chemistries

  if ( any(  f_2d(:)%class == "VOC" ) ) then !TMP .or. &
  !TMP           any(  f_3d(:)%class == "VOC" )  ) then
  ! was call Setup_VOC(), moved here Mar 2010
  !--------------------------------------------------------
  ! Searches through the advected species and colects the
  ! index and carbon content of nmhc/voc species, as they are
  ! defined in CM_ChemSpecs_ml
  !
  !--------------------------------------------------------
  !====================================================================
    do n = 1, NSPEC_ADV
      if(species( NSPEC_SHL+n )%carbons > 0 .and. &
         species( NSPEC_SHL+n )%name   /= "CO"  .and. &
         species( NSPEC_SHL+n )%name   /= "CH4" ) then

         nvoc = nvoc + 1
         voc_index(nvoc) = n
         voc_carbon(nvoc) = species( NSPEC_SHL+n )%carbons
      endif
    enddo
  !====================================================================
    !if (DEBUG  .and. MasterProc )then
    if ( MasterProc )then
      write(6,*) "Derived VOC setup returns ", nvoc, "vocs"
      write(6,"(a12,/,(20i3))")  "indices ", voc_index(1:nvoc)
      write(6,"(a12,/,(20i3))")  "carbons ", voc_carbon(1:nvoc)
    endif
  endif
endsubroutine Setups
!=========================================================================
subroutine Derived(dt,End_of_Day,ONLY_IOU)
!*** DESCRIPTION
!  Integration and averaging of chemical fields. Intended to be
!  a more flexible version of the old chemint routine.
!  Includes AOT40, AOT60 if present

  real, intent(in)    :: dt                   ! time-step used in intergrations
  logical, intent(in) :: End_of_Day           ! e.g. 6am for EMEP sites
  integer, intent(in), optional :: ONLY_IOU   ! IOU_INST update only instantenous fields,
                                              ! IOU_HOUR update (mean) hourly and inst. fields.

  character(len=len(f_2d%name)) :: name  !  See defs of f_2d
  character(len=len(f_2d%class)) :: class  !  See defs of f_2d
  character(len=len(f_2d%subclass)) :: subclass  !  See defs of f_2d
  character(len=TXTLEN_SHORT)    :: txt2
  real :: thour                          ! Time of day (GMT)
  real :: timefrac                       ! dt as fraction of hour (3600/dt)
  real :: dayfrac              ! fraction of day elapsed (in middle of dt)
  real :: af, xtot, fl0, fl1
  real, save :: km2_grid
  integer :: ntime                        ! 1...NTDAYS
  integer :: klow                         ! lowest extent of column data
  real, dimension(LIMAX,LJMAX) :: density ! roa[kgair m-3] when scale in ug, else 1
  real, dimension(LIMAX,LJMAX) :: tmpwork
  logical, dimension(LIMAX,LJMAX) :: mask2d
  real, dimension(LIMAX,LJMAX,KMAX_MID) :: inv_air_density3D
            ! Inverse of No. air mols/cm3 = 1/M
            ! where M =  roa (kgair m-3) * to_molec_cm3  when ! scale in ug,  else 1
  logical, save :: first_call = .true.
  integer :: igrp, ngrp   ! group methods
  logical :: needroa
  integer, save :: &      ! needed for PM25*,PM10*
    ind2d_pmfine=-999 ,ind3d_pmfine=-999,   &
    ind2d_pmwater=-999,ind3d_pmwater=-999,  &
    ind2d_pm10=-999   ,ind3d_pm10=-999
                                             
  integer :: imet_tmp, iix,ix,index
  real, pointer, dimension(:,:,:) :: met_p => null()

  logical, allocatable, dimension(:)   :: ingrp
  integer :: wlen,ispc,kmax
  integer,save :: n_Local_Pollutant, n_Total_Pollutant,&
       n_Local_Pollutant3D, n_Total_Pollutant3D

  timefrac = dt/3600.0
  thour = current_date%hour+current_date%seconds/3600.0

  daynumber=day_of_year(current_date%year,current_date%month,&
                        current_date%day)


  ! Just calculate once, and use where needed
  forall(i=1:limax,j=1:ljmax) density(i,j) = roa(i,j,KMAX_MID,1)

  !****** 2-D fields **************************

  do n = 1, num_deriv2d

    class = f_2d(n)%class
    subclass = f_2d(n)%subclass
    name  = f_2d(n)%name
    index = f_2d(n)%index

    if( dbgP .and. first_call ) &
       write(*,"(a,i3,9a)") "Derive2d-name-class", n, " C:", trim(class), &
            " U:", trim(f_2d(n)%unit), " N:", trim(name), ":END"



    !*** user-defined time-averaging. Here we have defined TADV and TVOC
    !    so that 8-hour daytime averages will be calculated.
    !    Just comment out if not wanted, or (better!) don't define any
    !    f_2d as TADV or TVOC

    if ( class == "TADV" .or. class == "TVOC" ) then
      if(thour <= 8.0 .or. thour > 16.0 ) cycle  ! Start next species
    end if

    ! hmix average at 00 and 12:
    if ( class == "HMIX00" .or. class == "XKSIG00" ) then
      if(thour /= 0.0 ) cycle  ! Start next species
    end if

    if ( class == "HMIX12" .or. class == "XKSIG12" ) then
      if(thour /= 12.0 ) cycle  ! Start next species
    end if

    !if ( DEBUG .and. MasterProc .and. first_call ) then
    if(MasterProc.and.first_call)&
      write(*,"(a,i4,1x,a,i4,1x,a)") "1st call Derived 2d", n, &
        trim(name), index, trim(class)

    select case ( class )

    case ( "MET2D")

     !DS May 2015
     ! Meteo fields are available through their names and a pointer, either
     ! from the read-in NWP fields (met%) or the derived met fields 
     ! (metderiv%), see MetFields_ml. We thus use the required name and see
     ! if we can find it in either met% or metderiv%

      imet_tmp = find_index(subclass, met(:)%name ) ! subclass has meteo name from MetFields 
      if( imet_tmp > 0 ) then
        met_p => met(imet_tmp)%field(:,:,:,1)
      else
        imet_tmp = find_index(subclass, derivmet(:)%name )
        if( imet_tmp > 0 ) met_p => derivmet(imet_tmp)%field(:,:,:,1)
      end if

      if( imet_tmp > 0 ) then
         kmax=1
         if(met(imet_tmp)%dim==3)kmax=KMAX_MID!take lowest level
         if( MasterProc.and.first_call) write(*,*) "MET2D"//trim(name), &
              imet_tmp, met_p(2,2,kmax)
         forall ( i=1:limax, j=1:ljmax )
            d_2d( n, i,j,IOU_INST) = met_p(i,j,kmax)
         end forall
         
         met_p => null()

      else ! Not found!
        if( first_call)  then
          if( MasterProc) write(*,*) "MET2D NOT FOUND"//trim(name)//":"//trim(subclass)
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = 0.0 ! UNDEF_R
          end forall
        end if
      end if

    ! The following can be deleted once testing of MET2D is finished...
    case ( "xm_i" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = xm_i(i,j)
      end forall
    case ( "lon" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = glon(i,j)
      end forall
    case ( "xm_j" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = xm_j(i,j)
      end forall
    case ( "lat" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = glat(i,j)
      end forall
    case ( "Kz_m2s" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = Kz_m2s(i,j,KMAX_BND-1)
      end forall
    case ( "ws_10m" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = ws_10m(i,j,1)
    end forall
    case ( "rh2m" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = rh2m(i,j,1)
    end forall

    case ( "SurfAreaPMF_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%PM_F,i,j)
      end forall
      if ( dbgP ) call write_debug(n,index, "SurfArea_NSDF")
    case ( "SurfAreaPM_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%PM,i,j)
      end forall
      if ( dbgP ) call write_debug(n,index, "SurfArea_NSDF")
    case ( "SurfAreaSSF_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%SS_F,i,j)
      end forall
      if ( dbgP ) call write_debug(n,index, "SurfArea_SSF")
    case ( "SurfAreaSSC_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%SS_C,i,j)
    end forall
    case ( "SurfAreaDUF_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%DU_F,i,j)
    end forall
    case ( "SurfAreaDUC_um2cm3" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%DU_C,i,j)
      end forall
    case ( "SurfAreaORIG_um2cm3" )
       forall ( i=1:limax, j=1:ljmax )
         d_2d( n, i,j,IOU_INST) = SurfArea_um2cm3(AERO%ORIG,i,j)
       end forall

    case ( "u_ref" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = u_ref(i,j)
    end forall

    case ( "SMI_deep" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SoilWater_deep(i,j,1)
    end forall
    if ( dbgP ) call write_debug(n,index, "SoilWater_DEEP")
    case ( "SMI_uppr" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SoilWater_uppr(i,j,1)
    end forall
    if ( dbgP ) call write_debug(n,index, "SoilWater_uppr")

    case ( "T2m" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = t2_nwp(i,j,1) - 273.15
    end forall
    case ( "Idirect" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = Idirect(i,j)
    end forall
    case ( "Idiffuse" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = Idiffuse(i,j)
    end forall

    case ( "XSNOW" ) ! Was not snow depth, but rather flag
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = Grid_snow(i,j)
      end forall

    case ( "SNratio" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = min(3.0,so2nh3_24hr(i,j))
      end forall

    case ( "PSURF" )

      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = ps(i,j,1)*0.01
        !NOT YET - keep hPa in sites:d_2d( n, i,j,IOU_INST) = ps(i,j,1)
      end forall

    case ( "HMIX", "HMIX00", "HMIX12" )

      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = pzpbl(i,j)
      end forall

      if ( dbgP ) then
       write(*,fmt="(a12,i4,f12.3)") "HMIX" , n , &
               d_2d(n,debug_li,debug_lj,IOU_INST)
      end if

    case ( "SURF_PPB_SPEC" )
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = xn_adv(index,i,j,KMAX_MID) &
                               * cfac(index,i,j)
      end forall
      if ( dbgP ) call write_debugadv(n,index, 1.0, "PPB OUTS")

    case ( "SURF_MASS_SPEC" )  ! Here we need density

      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = xn_adv(index,i,j,KMAX_MID) &
                               * cfac(index,i,j) * density(i,j)
      end forall

      if ( dbgP ) call write_debugadv(n,index, &
                               density(debug_li,debug_lj), "SURF_MASS")
!   case ( "SURF_molec_SHL" )        ! short-lived. Follows pattern of MAXSHL below
!
!         forall ( i=1:limax, j=1:ljmax )
!           d_2d( n, i,j,IOU_INST) = xn_shl(index,i,j,KMAX_MID)
!         end forall
!      if ( dbgP ) write(*,'(a,f8.2,3es12.3)') &
!          'SHLSHLmcc'//trim( species(index)%name), thour, &
!           xn_shl(index,debug_li,debug_lj,KMAX_MID), density(debug_li,debug_lj), to_molec_cm3
!
   ! WARNING CLASS PPB just means volume based..
    case ( "SURF_PPB_SHL" )        ! short-lived. Follows pattern of MAXSHL below
      if (  f_2d(n)%unit == "ppb"  ) then  !  NOT ENABLED SO FAR !
         forall ( i=1:limax, j=1:ljmax )
           d_2d( n, i,j,IOU_INST) = &
               xn_shl(index,i,j,KMAX_MID)  / (density(i,j)*to_molec_cm3)
         end forall
      else
         forall ( i=1:limax, j=1:ljmax )
           d_2d( n, i,j,IOU_INST) = xn_shl(index,i,j,KMAX_MID) 
         end forall
      end if

      if ( dbgP ) write(*,'(a,f8.2,3es12.3)') &
          'SHLSHLppb'//trim( species(index)%name), thour, &
           xn_shl(index,debug_li,debug_lj,KMAX_MID), density(debug_li,debug_lj), to_molec_cm3

    case ( "PM25water" )      !water
      forall ( i=1:limax, j=1:ljmax ) &
        d_2d( n, i,j,IOU_INST) = PM25_water_rh50(i,j)
      ind2d_pmwater = n

    case ( "PM25" )      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_2d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind2d_pmfine <1,"Missing PMFINE output for "//trim(class))
        call CheckStop(iadv_NO3_C <1,"Unknown specie NO3_C")
     endif

      forall(i=1:limax,j=1:ljmax) &
        d_2d(n,i,j,IOU_INST) = d_2d(ind2d_pmfine,i,j,IOU_INST) + &
                               fracPM25 * &
            ( xn_adv(iadv_NO3_C,i,j,KMAX_MID) * ug_NO3_C &
            ) * cfac(iadv_NO3_C,i,j) * density(i,j)

    case ( "PM25_rh50" )      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_2d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind2d_pmfine <1,"Missing PMFINE output for "//trim(class))
        call CheckStop(ind2d_pmwater<1,"Missing PM25water output for "//trim(class))
        call CheckStop(iadv_NO3_C <1,"Unknown specie NO3_C")
      endif

      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = d_2d(ind2d_pmfine ,i,j,IOU_INST) &
                               + d_2d(ind2d_pmwater,i,j,IOU_INST) &
                               + fracPM25 * &
            ( xn_adv(iadv_NO3_C,i,j,KMAX_MID) * ug_NO3_C &
            ) * cfac(iadv_NO3_C,i,j) * density(i,j)
      end forall

      if(DEBUG%DERIVED .and. debug_proc )  then
        write(*,*) "FRACTION PM25 2d", n, ind2d_pmfine, ind2d_pmwater
        i= debug_li; j=debug_lj
        write(*,"(a,4es12.3)") "Adding PM25 FRACTIONS:", &
          d_2d([ind2d_pmwater,ind2d_pmfine,n],i,j,IOU_INST), &
          fracPM25 * xn_adv(iadv_NO3_C,i,j,KMAX_MID) * ug_NO3_C &
                   * cfac(iadv_NO3_C,i,j) * density(i,j)
      endif

    case("PM25X")      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_2d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind2d_pmfine <1,"Missing PMFINE output for "//trim(class))
      endif
      if(any([iadv_NO3_C,iadv_EC_C_WOOD,iadv_EC_C_FFUEL,iadv_POM_C_FFUEL]<1))then
        if(first_call.and.MasterProc) write(*,*) &
          "WARNING: Derived - not all "//trim(class)//" species present. Skipping"
        cycle   !! Skip this case
      endif

      ! All this size class has the same cfac.
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = d_2d(ind2d_pmfine,i,j,IOU_INST) + &
                                 fracPM25 * &
            ( xn_adv(iadv_NO3_C      ,i,j,KMAX_MID) * ug_NO3_C       &
            + xn_adv(iadv_EC_C_WOOD  ,i,j,KMAX_MID) * ug_EC_C_WOOD   &
            + xn_adv(iadv_EC_C_FFUEL ,i,j,KMAX_MID) * ug_EC_C_FFUEL  &
            + xn_adv(iadv_POM_C_FFUEL,i,j,KMAX_MID) * ug_POM_C_FFUEL &
            ) * cfac(iadv_NO3_C,i,j) * density(i,j)
      end forall

    case("PM25X_rh50")      ! Need to add PMFINE + fraction NO3_c + water
      if(first_call)then
        call CheckStop(f_2d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind2d_pmfine <1,"Missing PMFINE output for "//trim(class))
        call CheckStop(ind2d_pmwater<1,"Missing PM25water output for "//trim(class))
      endif
      if(any([iadv_NO3_C,iadv_EC_C_WOOD,iadv_EC_C_FFUEL,iadv_POM_C_FFUEL]<1))then
        if(first_call.and.MasterProc) write(*,*) &
          "WARNING: Derived - not all "//trim(class)//" species present. Skipping"
        cycle   !! Skip this case
      endif

      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = d_2d(ind2d_pmfine ,i,j,IOU_INST) &
                               + d_2d(ind2d_pmwater,i,j,IOU_INST) &
                               + fracPM25 * &
            ( xn_adv(iadv_NO3_C      ,i,j,KMAX_MID) * ug_NO3_C       &
            + xn_adv(iadv_EC_C_WOOD  ,i,j,KMAX_MID) * ug_EC_C_WOOD   &
            + xn_adv(iadv_EC_C_FFUEL ,i,j,KMAX_MID) * ug_EC_C_FFUEL  &
            + xn_adv(iadv_POM_C_FFUEL,i,j,KMAX_MID) * ug_POM_C_FFUEL &
            ) * cfac(iadv_NO3_C,i,j) * density(i,j)
      end forall

    case("PM10_rh50")      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_2d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind2d_pm10   <1,"Missing PM10 output for "//trim(class))
        call CheckStop(ind2d_pmwater<1,"Missing PM25water output for "//trim(class))
      endif

      forall(i=1:limax,j=1:ljmax) &
        d_2d(n,i,j,IOU_INST) = d_2d(ind2d_pm10   ,i,j,IOU_INST) &
                             + d_2d(ind2d_pmwater,i,j,IOU_INST)

    case("AOD:GROUP","AOD:SPEC")  !/ Aerosol Optical Depth (new system)
      if(first_call)call AOD_init("Derived:"//trim(class))
      wlen=find_index(f_2d(n)%subclass,wavelength)! e.g. search "550nm" on array of wavelengths
      if(first_call)then
        call CheckStop(wlen<1,&
          "Unknown AOD wavelength "//trim(f_2d(n)%subclass))
        call CheckStop(.not.wanted_wlen(wlen),&
          "Unwanted AOD wavelength "//trim(f_2d(n)%subclass))        
      endif
      
      ngrp = size(aod_grp)
      allocate(ingrp(ngrp))
      select case(class)
      case("AOD:GROUP")
        igrp = f_2d(n)%index
        do i=1,ngrp
          ingrp(i)=any(aod_grp(i)==chemgroups(igrp)%ptr(:))
        enddo
      case("AOD:SPEC")
        ispc = f_2d(n)%index
        ingrp(:)=(aod_grp(:)==(ispc+NSPEC_SHL))
      endselect
      forall ( i=1:limax, j=1:ljmax )&
        d_2d( n, i,j,IOU_INST) = SUM(AOD(:,i,j,wlen),MASK=ingrp)
      deallocate(ingrp)

    case ( "MAXADV" )
      if (  f_2d(n)%unit == "ppb"  ) then

         d_2d( n, 1:limax,1:ljmax,IOU_DAY) = &
           max( d_2d( n, 1:limax,1:ljmax,IOU_DAY),  &
                xn_adv(index,1:limax,1:ljmax,KMAX_MID)  &
               * cfac(index,1:limax,1:ljmax) )
         txt2 = "MAXADV ppb for " // trim( f_2d(n)%name)
       else
         d_2d( n, 1:limax,1:ljmax,IOU_DAY) = &
           max( d_2d( n, 1:limax,1:ljmax,IOU_DAY),  &
                xn_adv(index,1:limax,1:ljmax,KMAX_MID)  &
               * cfac(index,1:limax,1:ljmax) * density(1:limax,1:ljmax) )
         txt2 = "MAXADV ug for " // trim( f_2d(n)%name)
       end if

      if ( dbgP ) call write_debugadv(n,index, &
                               density(debug_li,debug_lj), txt2 )

      !Monthly and yearly ARE averaged over days
      if(End_of_Day)then
        d_2d(n,:,:,IOU_MON )  = d_2d(n,:,:,IOU_MON )  + d_2d(n,:,:,IOU_DAY)
        nav_2d(n,IOU_MON) = nav_2d(n,IOU_MON) + 1
        if(    current_date%month >= 4 &
           .or.current_date%month <= 9 )then
        d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
        nav_2d(n,IOU_YEAR) = nav_2d(n,IOU_YEAR) + 1
        endif
      endif


    case ( "MAXSHL" )        ! Daily maxima - short-lived
      if (  f_2d(n)%unit /= "ppb"  ) then  ! Mix ratio so far
         forall ( i=1:limax, j=1:ljmax )
           d_2d( n, i,j,IOU_DAY) = max( d_2d( n, i,j,IOU_DAY), &
               xn_shl(index,i,j,KMAX_MID) )
         end forall
      else
         forall ( i=1:limax, j=1:ljmax )
           d_2d( n, i,j,IOU_DAY) = max( d_2d( n, i,j,IOU_DAY), &
               xn_shl(index,i,j,KMAX_MID)  / (density(i,j)*to_molec_cm3) )
         end forall
      end if


      if ( dbgP ) then
         write(*, *) "SHL:MAX.,to_molec_cm3 ", n, index  , to_molec_cm3
         write(*,fmt="(a12,2i4,4es12.3)") "SHL MAX. ", n, index  &
                , d_2d(n,debug_li,debug_lj,IOU_DAY) &
                ,  xn_shl(index,debug_li,debug_lj,KMAX_MID)  &
                ,  density(debug_li,debug_lj), to_molec_cm3
      end if

      !Monthly and yearly ARE averaged over days
      if(End_of_Day)then
        d_2d(n,:,:,IOU_MON ) = d_2d(n,:,:,IOU_MON ) + d_2d(n,:,:,IOU_DAY)
        nav_2d(n,IOU_MON) = nav_2d(n,IOU_MON) + 1
        if(    current_date%month >= 4 &
           .or.current_date%month <= 9 )then
        d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
        nav_2d(n,IOU_YEAR) = nav_2d(n,IOU_YEAR) + 1
        endif
      endif

    case ( "VOC", "TVOC" )

      call voc_2dcalc()

    case( "GRIDAOT" )!  Hardly used these days. The vegetation-specific
                     !  AOTs are handled in the Mosaic class and as
                     !  part of the dry dep calculations.
      if(first_call)&
        call CheckStop(iadv_o3<1,"Unknown specie O3")

      d_2d(n, 1:limax, 1:ljmax, IOU_INST) = Calc_GridAOTx( f_2d(n)%index )

      if( DEBUG%AOT .and. debug_proc ) then
        call datewrite("AOTDEBUG" // trim(f_2d(n)%name), n, &
         (/ zen(debug_li,debug_lj), real(f_2d(n)%index), &
            xn_adv(iadv_O3,debug_li,debug_lj,KMAX_MID)*&
               cfac(iadv_O3,debug_li,debug_lj)*PPBINV, &
            d_2d(n, debug_li, debug_lj, IOU_INST )  /) )
      end if

    case( "SOMO" )
      if(first_call)&
        call CheckStop(iadv_o3<1,"Unknown specie O3")

      !dt/7200: half a dt time step in hours
      !dayfrac "points" to the middle of the integration step
      dayfrac= (thour-(dt/7200.))/24. !must be < 1
      ntime=int(dayfrac*NTDAY )+1 !must be >=1 and <= NTDAY
      if(dayfrac<0)ntime=NTDAY !midnight

      !last value  (not averaged):
      D2_O3_DAY( : , : , ntime) =&
       xn_adv(iadv_o3,:,:,KMAX_MID)*cfac(iadv_o3,:,:)*PPBINV

      if(dayfrac<0)then !only at midnight: write on d_2d
        call somo_calc( n, f_2d(n)%index, DEBUG%DERIVED .and. debug_proc )
        d_2d(n,:,:,IOU_MON )  = d_2d(n,:,:,IOU_MON )  + d_2d(n,:,:,IOU_DAY)

        ! if(current_date%month>=4.and.current_date%month<=9)then
        d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
        !NB overwritten anyway D2_O3_DAY = 0.
      endif

    case("PREC","WDEP","DDEP","VG","Rs","Rns","Gns","Mosaic","POD","SPOD","AOT")
    ! Nothing to do - all set in My_DryDep
      ! if(dbgP) write(*,"(2a,i4,a,es12.3)")"PROCESS ",trim(class),&
      !   n, trim(f_2d(n)%name), d_2d(n,debug_li,debug_lj,IOU_INST)

    case('FLYmax6h','FLYmax6h:SPEC')    ! Fly Level, 6 hourly maximum
      ! fl00-20: 0 to 20 kfeet, fl20-35: 20 to 35 kfeet, fl35-50: 35 to 50 kfeet
      read(subclass,"(a2,i2,a1,i2)") txt2, k, txt2, l
      fl0=k*304.8 ! 1e3 [feet] to [m]
      fl1=l*304.8 ! 1e3 [feet] to [m]
      call Units_Scale(f_2d(n)%unit,index,af,needroa=needroa) ! only want needroa
      if(needroa)then
        tmpwork=maxval(xn_adv(index,:,:,:)*roa(:,:,:,1),dim=3,&
                       mask=z_mid>=fl0.and.z_mid<=fl1)
      else
        tmpwork=maxval(xn_adv(index,:,:,:),dim=3,&
                       mask=z_mid>=fl0.and.z_mid<=fl1)
      endif
      forall(i=1:limax,j=1:ljmax)&  ! use IOU_YEAR as a buffer
        d_2d(n,i,j,IOU_YEAR)=max(d_2d(n,i,j,IOU_YEAR),tmpwork(i,j))
    case('FLYmax6h:GROUP')           ! Fly Level, 6 hourly maximum
      ! fl00-02: 0 to 2 kfeet, fl02-35: 2 to 35 kfeet, fl35-50: 35 to 50 kfeet
      read(subclass,"(a2,i2,a1,i2)") txt2, k, txt2, l
      fl0=k*304.8 ! 1e3 [feet] to [m]
      fl1=l*304.8 ! 1e3 [feet] to [m]
      if(dbgP)print *,trim(subclass),fl0,fl1
      do k=1,KMAX_MID
        mask2d(:,:)=(z_mid(:,:,k)>=fl0.and.z_mid(:,:,k)<=fl1)
        if(.not.(any(mask2d)))cycle
        if(dbgP)print *,trim(subclass),k,count(mask2d)
        call group_calc(tmpwork(:,:),roa(:,:,k,1),f_2d(n)%unit,k,index)
        forall(i=1:limax,j=1:ljmax,mask2d(i,j))&  ! use IOU_YEAR as a buffer
          d_2d(n,i,j,IOU_YEAR)=max(d_2d(n,i,j,IOU_YEAR),tmpwork(i,j))
      enddo
    case ("COLUMN","COLUMN:SPEC") ! unit conversion factor stored in f_2d(n)%scale
      read(f_2d(n)%subclass,"(a1,i2)") txt2, klow ! Connvert e.g. k20 to klow=20
      do j = 1, ljmax
        do i = 1, limax
          k = 1
          tmpwork(i,j) =  &
            xn_adv(index,i,j,k)*roa(i,j,k,1)*(z_bnd(i,j,k)-z_bnd(i,j,k+1))
          do k = 2, klow   !!! KMAX_MID
            tmpwork(i,j) = tmpwork(i,j) + &
              xn_adv(index,i,j,k)*roa(i,j,k,1)*(z_bnd(i,j,k)-z_bnd(i,j,k+1))

            if(DEBUG%COLUMN.and.dbgP.and.&
              i==debug_li.and.j==debug_lj) &
              write(*,"(a,3i4,a4,f8.3,f8.1,2es12.3)") &
                trim(f_2d(n)%name), n, index, k, " => ", &
                  roa(i,j,k,1), z_bnd(i,j,k)-z_bnd(i,j,k+1), &
                  xn_adv(index,i,j,k),tmpwork(i,j)
          enddo ! k
          d_2d(n,i,j,IOU_INST) = tmpwork(i,j) ! unit conversion
                   ! is completed elsewere by *f_2d(n)%scale
        enddo !i
      enddo !j
      if(dbgP) write(*,"(a18,es12.3)") &
        "COLUMN:SPEC d2_2d",d_2d(n,debug_li,debug_lj,IOU_INST)*f_2d(n)%scale

    case("COLUMN:GROUP")
      igrp = f_2d(n)%index
      call CheckStop(igrp<1,"NEG GRP "//trim(f_2d(n)%name))
      call CheckStop(igrp>size(chemgroups(:)%name), &
                            "Outside GRP "//trim(f_2d(n)%name))
      read(f_2d(n)%subclass,"(a1,i2)") txt2, klow ! Connvert e.g. k20 to klow=20
      d_2d(n,:,:,IOU_INST) = 0.0
      do k=1,klow
        call group_calc(tmpwork(:,:),roa(:,:,k,1),f_2d(n)%unit,k,igrp)
        forall(i=1:limax,j=1:ljmax) &
          d_2d(n,i,j,IOU_INST) = d_2d(n,i,j,IOU_INST) &
            + tmpwork(i,j)*(z_bnd(i,j,k)-z_bnd(i,j,k+1)) ! unit conversion in group_calc
      enddo
      if(dbgP) write(*,"(a18,es12.3)") &
        "COLUMN:GROUP d2_2d",d_2d(n,debug_li,debug_lj,IOU_INST)*f_2d(n)%scale

    case ( "EcoFrac" ) ! ODD TO HAVE FRAC AND AREA BELOW:"ECOAREA" )

      if( .not. first_call ) cycle ! Only need to do once
      if( f_2d(n)%Index == FULL_ECOGRID ) then
        km2_grid = (GRIDWIDTH_M*GRIDWIDTH_M) * 1.0e-6 ! km2
        forall ( i=1:limax, j=1:ljmax )
            d_2d(n,i,j,IOU_YEAR) =  EcoSystemFrac( f_2d(n)%Index ,i,j)&
                  * KM2_GRID /xm2(i,j)
        end forall
      else
        forall ( i=1:limax, j=1:ljmax )
            d_2d(n,i,j,IOU_YEAR) =  EcoSystemFrac( f_2d(n)%Index ,i,j)
        end forall
      end if
      if( dbgP ) &
        write(*,"(a18,a,i4,a,2es12.3)") "ECOD2D ", &
           " f2d:", f_2d(n)%Index, &
           " Frac", EcoSystemFrac( f_2d(n)%Index, debug_li,debug_lj), &
           !!" Index: ", DepEcoSystem(n)%Index, &
              d_2d( n, debug_li, debug_lj, IOU_YEAR)

    case ( "NatEmis" ) !emissions in kg/m2/s converted??

      forall ( i=1:limax, j=1:ljmax )
          d_2d(n,i,j,IOU_INST) =  EmisNat( f_2d(n)%Index,i,j )
      end forall
      !Not done, keep mg/m2  * GridArea_m2(i,j)
      if ( dbgP ) call write_debug(n,f_2d(n)%Index, "NatEmis")
      if( dbgP ) &
        call datewrite("NatEmis-in-Derived, still kg/m2/s", &
          f_2d(n)%Index, (/ EmisNat( f_2d(n)%Index, debug_li,debug_lj) /) )

    case ( "SnapEmis" ) !emissions in kg/m2/s converted??

      forall ( i=1:limax, j=1:ljmax )
          d_2d(n,i,j,IOU_INST) =  SumSnapEmis( i,j, f_2d(n)%Index)
      end forall
      !not done, to keep mg/m2 * GridArea_m2(i,j)
      if( dbgP .and. f_2d(n)%Index == 3  ) & ! CO:
        call datewrite("SnapEmis-in-Derived, still kg/m2/s", n, & !f_2d(n)%Index,&
              (/   SumSnapEmis( debug_li,debug_lj, f_2d(n)%Index ) /) )

    case ( "Emis_mgm2_DMS" )      ! DMS
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = O_DMS%map(i,j)
      end forall

    case("Local_Pollutant")   ! for uEMEP, under development
       do j=1,ljmax 
          do i=1,limax
             xtot=0.0
             do iix=1,uEMEP%Nix
                ix=uEMEP%ix(iix)
                xtot=xtot+(xn_adv(ix,i,j,kmax_mid)*species_adv(ix)%molwt)&
                 *(dA(kmax_mid)+dB(kmax_mid)*ps(i,j,1))/ATWAIR/GRAV
             enddo
             d_2d( n, i,j,IOU_INST) = loc_frac(i,j,kmax_mid,1)*xtot
          enddo
       enddo
       n_Local_Pollutant=n

    case("Total_Pollutant")   ! for uEMEP, under development
       do j=1,ljmax 
          do i=1,limax
             xtot=0.0
             do iix=1,uEMEP%Nix
                ix=uEMEP%ix(iix)
                xtot=xtot+(xn_adv(ix,i,j,kmax_mid)*species_adv(ix)%molwt)&
                     *(dA(kmax_mid)+dB(kmax_mid)*ps(i,j,1))/ATWAIR/GRAV
             enddo
             d_2d( n, i,j,IOU_INST) = xtot
          enddo
       enddo
       n_Total_Pollutant=n

    case("Local_Fraction")    ! for uEMEP, under development
      forall(i=1:limax,j=1:ljmax)
        d_2d(n,i,j,IOU_INST) = 0.0
        d_2d(n,i,j,IOU_HOUR) = d_2d(n_Local_Pollutant,i,j,IOU_HOUR)/&
                              (d_2d(n_Total_Pollutant,i,j,IOU_HOUR)+1.E-30)
        d_2d(n,i,j,IOU_DAY ) = d_2d(n_Local_Pollutant,i,j,IOU_DAY)/&
                              (d_2d(n_Total_Pollutant,i,j,IOU_DAY)+1.E-30)
        d_2d(n,i,j,IOU_MON ) = d_2d(n_Local_Pollutant,i,j,IOU_MON)/&
                              (d_2d(n_Total_Pollutant,i,j,IOU_MON)+1.E-30)
        d_2d(n,i,j,IOU_YEAR) = d_2d(n_Local_Pollutant,i,j,IOU_YEAR)/&
                              (d_2d(n_Total_Pollutant,i,j,IOU_YEAR)+1.E-30)
      endforall


     case ( "EmisSplit_mgm2" )      ! Splitted total emissions (Inclusive natural)
      forall ( i=1:limax, j=1:ljmax )
        d_2d( n, i,j,IOU_INST) = SumSplitEmis(i,j,f_2d(n)%Index)
      end forall

    case ( "EXT" )
    ! Externally set for IOU_INST (in other routines); so no new work
    ! needed except decision to accumalate to yearly or not.
      if(dbgP) write(*,"(a18,i4,a12,a4,es12.3)")"EXT d_2d",&
        n, f_2d(n)%name, " is ", d_2d(n,debug_li,debug_lj,IOU_INST)

    case ( "SURF_MASS_GROUP","SURF_PPB_GROUP" ) !
      igrp = f_2d(n)%index
      call CheckStop(igrp<1,"NEG GRP "//trim(f_2d(n)%name))
      call CheckStop(igrp>size(chemgroups(:)%name), &
                            "Outside GRP "//trim(f_2d(n)%name))
      ngrp = size(chemgroups(igrp)%ptr)

      if(chemgroups(igrp)%name == "PMFINE" .and. ind2d_pmfine<0) then
        ind2d_pmfine = n
        if(MasterProc) write(*,"(a,2i4,2a15)") "FOUND FINE FRACTION ",&
          n, ind2d_pmfine, trim(chemgroups(igrp)%name), trim(f_2d(n)%name)
      endif
      if(chemgroups(igrp)%name == "PM10" .and. ind2d_pm10<0) then
        ind2d_pm10 = n
        if(MasterProc) write(*,"(a,2i4,2a15)") "FOUND PM10 FRACTION ",&
          n, ind2d_pm10, trim(chemgroups(igrp)%name), trim(f_2d(n)%name)
      endif
      if(dbg0) then
        write(*,"(a,3i5,2(1x,a))")"CASEGRP:"//trim(f_2d(n)%name), n, igrp,&
             ngrp, trim(class), trim(subclass) ! FSOA igrp=109, ngrp=10
        write(*,"(a,88i4)") "CASEGRP:", chemgroups(igrp)%ptr
        write(*,*) "CASEGRPunit ", trim(f_2d(n)%unit)
      endif
      call group_calc(d_2d(n,:,:,IOU_INST),density,f_2d(n)%unit,0,igrp,&
                      semivol=(f_2d(n)%subclass=='FSOA'))

      if(DEBUG%DERIVED.and.debug_proc)then
        i= debug_li; j=debug_lj
        if(n==ind2d_pmfine ) &
          write(*,"(a,i4,es12.3)") "PMFINE FRACTION:"   ,n,d_2d(n,i,j,IOU_INST)
        if(n==ind2d_pm10   ) &
          write(*,"(a,i4,es12.3)") "PM10 FRACTION:"     ,n,d_2d(n,i,j,IOU_INST)
        write(*,*) "CASErho     ", density(i,j)
      endif

    case("USET")
      if(dbgP) write(*,"(a18,i4,a12,a4,es12.3)")"USET d_2d",&
        n, f_2d(n)%name, " is ", d_2d(n,debug_li,debug_lj,IOU_INST)

    case  default

      if ( dbgP ) then
         if( i == debug_li .and. j == debug_lj ) &
           write(*,"(a,i3,4a)") "My_Deriv Defaults called n=",&
              n, " Type ",trim(class), " Name ", trim( f_2d(n)%name )

           write(*,"(a,i3,i8,i4,a)") &
              "My_Deriv index?, nav? length?, class? ", index,&
              nav_2d(n,IOU_INST), len(f_2d%class), trim(f_2d(n)%class)
           write(*,*) "My_Deriv index?, avg ", f_2d(n)%avg
       end if

       call My_DerivFunc( d_2d(n,:,:,IOU_INST), class ) ! , density )

    endselect

    !*** add to daily, monthly and yearly average, and increment counters
    select case(f_2d(n)%class)
    case('FLYmax6h','FLYmax6h:SPEC','FLYmax6h:GROUP')
    ! Fly Level, 6 hourly maximum:  only need IOU_HOUR,IOU_HOUR_INST
      d_2d(n,:,:,IOU_INST) = d_2d(n,:,:,IOU_YEAR) ! use IOU_YEAR as a buffer
      d_2d(n,:,:,IOU_HOUR) = d_2d(n,:,:,IOU_YEAR)
      if(mod(current_date%hour,6)==0)&  ! reset buffer
        d_2d(n,:,:,IOU_YEAR)=0.0        
    case("MAXADV","MAXSHL","SOMO")
    !  MAXADV and MAXSHL and SOMO needn't be summed here.
    !  These d_2d ( MAXADV, MAXSHL, SOMO) are set elsewhere
    case default
      af = 1.0 ! accumulation factor
      if(f_2d(n)%dt_scale) af=dt_advec !need to scale with dt_advec

      ! only accumulate outputs if they are wanted (will be written out)
      do iou=1,LENOUT2D
        if(iou==IOU_INST)cycle
        if(.not.wanted_iou(iou,f_2d(n)%iotype,ONLY_IOU))cycle
        d_2d(n,:,:,iou) = d_2d(n,:,:,iou) + d_2d(n,:,:,IOU_INST)*af
        if(f_2d(n)%avg) nav_2d(n,iou) = nav_2d(n,iou) + 1
      enddo
    endselect

  enddo   ! num_deriv2d

  !****** 3-D fields **************************

  if(dbgP)& ! RUN through indices etc.
    write(*, "(a12,2i4,f12.3)") "3D3D TIME ",  me, num_deriv3d, &
            (current_date%hour+current_date%seconds/3600.0)


  do n = 1, num_deriv3d

    index = f_3d(n)%index
    class   = f_3d(n)%class

    if(f_3d(n)%unit=="ppb") then
      inv_air_density3D(:,:,:) = 1.0
    else
      forall( i=1:limax, j=1:ljmax, k=1:KMAX_MID )&
        inv_air_density3D(i,j,k) = 1.0/( roa(i,j,k,1) * to_molec_cm3 )
    endif

    select case (class)

    case ( "MET3D" )

      imet_tmp = find_index(f_3d(n)%subclass, met(:)%name ) ! subclass has meteo name from MetFields 
      if(imet_tmp>0) then
        if(met(imet_tmp)%dim==3)then
          if( MasterProc.and.first_call) write(*,*) "MET3D"//trim(f_3d(n)%name), &
                imet_tmp, met(imet_tmp)%field(2,2,KMAX_MID,1)
          forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
            d_3d(n,i,j,k,IOU_INST)=met(imet_tmp)%field(i,j,lev3d(k),1)
        elseif(MasterProc.and.first_call)then
          write(*,*) "Warning: requested 2D field with MET3D: ",trim(f_3d(n)%name)
        endif
      elseif(first_call)then
        if(MasterProc) write(*,*) "MET3D NOT FOUND"//trim(f_3d(n)%name)//":"//trim(f_3d(n)%subclass)
        d_3d(n,:,:,:,IOU_INST)=0.0
      endif

    ! Simple advected species:
    case ( "ADV" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_adv(index,i,j,lev3d(k))

    case ( "BGN" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_bgn(index,i,j,lev3d(k))
  
    case ( "PM25water" )         !particle water
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=PM25_water(i,j,lev3d(k))
      ind3d_pmwater = n

    case ( "PM25" )      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_3d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind3d_pmfine <1,"Missing PMFINE output for "//trim(class))
        call CheckStop(iadv_NO3_C <1,"Unknown specie NO3_C")
      endif

      forall (i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST) = d_3d(ind3d_pmfine,i,j,k,IOU_INST) + &
                                 fracPM25 * &
            ( xn_adv(iadv_NO3_C,i,j,lev3d(k)) * ug_NO3_C &
            ) * roa(i,j,lev3d(k),1)

    case ( "PM25_wet" )         ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_3d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind3d_pmfine <1,"Missing PMFINE output for "//trim(class))
        call CheckStop(ind3d_pmwater<1,"Missing PM25water output for "//trim(class))
        call CheckStop(iadv_NO3_C <1,"Unknown specie NO3_C")
      endif

      forall (i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST) = d_3d(ind3d_pmfine ,i,j,k,IOU_INST) &
                               + d_3d(ind3d_pmwater,i,j,k,IOU_INST) &
                               + fracPM25 * &
            ( xn_adv(iadv_NO3_C,i,j,lev3d(k)) * ug_NO3_C &
            ) * roa(i,j,lev3d(k),1)

      if(DEBUG%DERIVED .and. debug_proc )  then
        write(*,*) "FRACTION PM25 3d", n, ind3d_pmfine, ind3d_pmwater
        i= debug_li; j=debug_lj; k=1; l=lev3d(k)
        write(*,"(a,4es12.3)") "Adding PM25FRACTIONS:", &
          d_3d([ind3d_pmwater,ind3d_pmfine,n],i,j,k,IOU_INST), &
          ug_NO3_C * xn_adv(iadv_NO3_C,i,j,l) * roa(i,j,l,1)
      endif

    case("PM10_wet")      ! Need to add PMFINE + fraction NO3_c
      if(first_call)then
        call CheckStop(f_3d(n)%unit(1:2)/="ug","Wrong unit for "//trim(class))
        call CheckStop(ind3d_pm10   <1,"Missing PM10 output for "//trim(class))
        call CheckStop(ind3d_pmwater<1,"Missing PM25water output for "//trim(class))
      endif

      forall (i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST) = d_3d(ind3d_pm10   ,i,j,k,IOU_INST) &
                               + d_3d(ind3d_pmwater,i,j,k,IOU_INST)

    case ("XKSIG00", "XKSIG12" ) !hf hmix Kz_m2s
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=Kz_m2s(i,j,lev3d(k))
  
    case ("TH" ) ! Pot. temp (needed for cross sections)
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=th(i,j,lev3d(k),1)
  
    case ("T" ) ! Absolute Temperature
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=th(i,j,lev3d(k),1)&
            *exp(KAPPA*log((A_mid(lev3d(k)) &
                          + B_mid(lev3d(k))*ps(i,j,1))*1.e-5))

    case ( "MAX3DSHL" ) ! Daily maxima - short-lived
      call CheckStop(f_3d(n)%unit=="ppb","Asked for MAX3DSHL ppb ")
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=max(d_3d(n,i,j,k,IOU_INST),&
                             xn_shl(index,i,j,lev3d(k)) &
                       *inv_air_density3D(i,j,lev3d(k)))

      if(dbgP) write(*,"(a13,i4,f8.3,3es12.3)") "3D3D MAX3DSHL", n, thour, &
        xn_shl(index,debug_li,debug_lj,KMAX_MID), &
        1.0/inv_air_density3D(debug_li,debug_lj,KMAX_MID), &
        d_3d(n,debug_li,debug_lj,num_lev3d,IOU_INST)

    case ( "MAX3DADV" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=max(d_3d(n,i,j,k,IOU_INST),&
                             xn_adv(index,i,j,lev3d(k)))

      if(dbgP) write(*,"(a12,i4,f8.3,4es12.3)") "SET MAX3DADV", n, thour, &
        xn_adv(index,debug_li,debug_lj,KMAX_MID), &
        d_3d(n,debug_li,debug_lj,num_lev3d,IOU_INST)

    case ( "SHL" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_shl(index,i,j,lev3d(k))&
                         *inv_air_density3D(i,j,lev3d(k))

    case ( "VOC" )
      call voc_3dcalc()

    case ( "3D_PPB_SPEC" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_adv(index,i,j,lev3d(k))

      if(dbgP) call write_debugadv(n,index, 1.0, "3D PPB OUTS")

    case ( "3D_PPB_SHL" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_shl(index,i,j,lev3d(k))

    case ( "3D_MASS_SPEC" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_adv(index,i,j,lev3d(k))*roa(i,j,lev3d(k),1)

      if(dbgP) call write_debugadv(n,index, 1.0, "3D UG OUTS")

    case ( "3D_MASS_GROUP" ) !
      igrp = f_3d(n)%index
      call CheckStop(igrp<1,"NEG GRP "//trim(f_3d(n)%name))
      call CheckStop(igrp>size(chemgroups(:)%name), &
                            "Outside GRP "//trim(f_3d(n)%name))                            
      ngrp = size(chemgroups(igrp)%ptr)
      if(chemgroups(igrp)%name == "PMFINE" .and. ind3d_pmfine<0) then
        ind3d_pmfine = n
        if(MasterProc) write(*,"(a,2i4,2a15)") "FOUND FINE 3d FRACTION ",&
          n, ind3d_pmfine, trim(chemgroups(igrp)%name), trim(f_3d(n)%name)
      endif
      if(chemgroups(igrp)%name == "PM10" .and. ind3d_pm10<0) then
        ind3d_pm10 = n
        if(MasterProc) write(*,"(a,2i4,2a15)") "FOUND PM10 3d FRACTION ",&
          n, ind3d_pm10, trim(chemgroups(igrp)%name), trim(f_3d(n)%name)
      endif
      if(dbg0) then
        write(*,*) "3DCASEGRP ", n, igrp, ngrp, trim(class)
        write(*,*) "3DCASENAM ", trim(f_3d(n)%name)
        write(*,*) "3DCASEGRP:", chemgroups(igrp)%ptr
        write(*,*) "3DCASEunit", trim(f_3d(n)%unit)
      endif
      do k=1,num_lev3d
        call group_calc(d_3d(n,:,:,k,IOU_INST),roa(:,:,lev3d(k),1),&
                        f_3d(n)%unit,lev3d(k),igrp)
      enddo

      if(DEBUG%DERIVED.and.debug_proc)then
        i= debug_li; j=debug_lj; k=1; l=lev3d(k)
        if(n==ind3d_pmfine ) &
          write(*,"(a,i4,es12.3)") "PMFINE 3d FRACTION:",n,d_3d(n,i,j,k,IOU_INST)
        if(n==ind3d_pm10   ) &
          write(*,"(a,i4,es12.3)") "PM10 3d FRACTION:"  ,n,d_3d(n,i,j,k,IOU_INST)
        write(*,*) "CASErho     ", roa(i,j,l,1)
      endif

    case ( "Kz" )
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=Kz_m2s(i,j,lev3d(k))

    case ("Z_MID","Z")    ! Mid-layer heigh
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=z_mid(i,j,lev3d(k))

    case ("Z_BND","Zlev") ! Mid-layer heigh
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=z_bnd(i,j,lev3d(k))

    case("dZ_BND","dZ")   ! level thickness
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=z_bnd(i,j,lev3d(k))-z_bnd(i,j,lev3d(k)+1)

    case("wind_speed_3D")
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=sqrt(u_mid(i,j,lev3d(k))**2+v_mid(i,j,lev3d(k))**2)

    case("EXT:GROUP","EXT:SPEC")  !/ Extinction coefficient (new system)
      if(first_call)call AOD_init("Derived:"//trim(class))
      wlen=find_index(f_3d(n)%subclass,wavelength)! e.g. search "550nm" on array of wavelengths
      if(first_call)then
        call CheckStop(wlen<1,&
          "Unknown EXT wavelength "//trim(f_3d(n)%subclass))
        call CheckStop(.not.(wanted_wlen(wlen).and.wanted_ext3d),&
          "Unwanted EXT wavelength "//trim(f_3d(n)%subclass))        
      endif

      ngrp = size(aod_grp)
      allocate(ingrp(ngrp))
      select case(class)
      case("EXT:GROUP")
        igrp = f_3d(n)%index
        do i=1,ngrp
          ingrp(i)=any(aod_grp(i)==chemgroups(igrp)%ptr(:))
        enddo
      case("EXT:SPEC")
        ispc = f_3d(n)%index
        ingrp(:)=(aod_grp(:)==(ispc+NSPEC_SHL))
      endselect
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=SUM(Extin_coeff(:,i,j,lev3d(k),wlen),MASK=ingrp)
      deallocate(ingrp)

    case("Local_Pollutant3D")   ! for uEMEP, under development
      do l=1,num_lev3d
        k=lev3d(l)
        do j=1,ljmax 
          do i=1,limax             
             xtot=0.0
             do iix=1,uEMEP%Nix
                ix=uEMEP%ix(iix)
                xtot=xtot+(xn_adv(ix,i,j,k)*species_adv(ix)%molwt)&
                 *(dA(k)+dB(k)*ps(i,j,1))/ATWAIR/GRAV*1.0E6
             enddo
             d_3d(n,i,j,l,IOU_INST) = loc_frac(i,j,k,1)*xtot
          enddo
        enddo
      enddo
      n_Local_Pollutant3D=n
     !write(*,*)loc_frac(5,5,kmax_mid,1),loc_frac(5,5,kmax_mid-1,1)

    case("Total_Pollutant3D")   ! for uEMEP, under development
      do l=1,num_lev3d
        k=lev3d(l)
        do j=1,ljmax 
          do i=1,limax
            xtot=0.0
            do iix=1,uEMEP%Nix
              ix=uEMEP%ix(iix)
              xtot=xtot+(xn_adv(ix,i,j,k)*species_adv(ix)%molwt)&
                   *(dA(k)+dB(k)*ps(i,j,1))/ATWAIR/GRAV*1.0E6
            enddo
            d_3d(n,i,j,l,IOU_INST) = xtot
          enddo
        enddo
      enddo
      n_Total_Pollutant3D=n

    case("Local_Fraction3D")    ! for uEMEP, under development
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d)
        d_3d(n,i,j,k,IOU_INST) = 0.0
        d_3d(n,i,j,k,IOU_HOUR) = d_3d(n_Local_Pollutant3D,i,j,k,IOU_HOUR)/&
                                (d_3d(n_Total_Pollutant3D,i,j,k,IOU_HOUR)+1.E-30)
        d_3d(n,i,j,k,IOU_DAY ) = d_3d(n_Local_Pollutant3D,i,j,k,IOU_DAY)/&
                                (d_3d(n_Total_Pollutant3D,i,j,k,IOU_DAY)+1.E-30)
        d_3d(n,i,j,k,IOU_MON ) = d_3d(n_Local_Pollutant3D,i,j,k,IOU_MON)/&
                                (d_3d(n_Total_Pollutant3D,i,j,k,IOU_MON)+1.E-30)
        d_3d(n,i,j,k,IOU_YEAR) = d_3d(n_Local_Pollutant3D,i,j,k,IOU_YEAR)/&
                                (d_3d(n_Total_Pollutant3D,i,j,k,IOU_YEAR)+1.E-30)
      endforall

    case("USET")
      if(dbgP) write(*,"(a18,i4,a12,a4,es12.3)")"USET d_3d",&
        n, f_3d(n)%name, " is ", d_3d(n,debug_li,debug_lj,num_lev3d,IOU_INST)

    case default
      write(*,"(a,2i3,3a)") "*** NOT FOUND",n,index, trim(f_3d(n)%name),&
               ";Class:", trim(f_3d(n)%class)
      write(unit=errmsg,fmt=*) "Derived 3D class NOT FOUND", n, index, &
                       trim(f_3d(n)%name),trim(f_3d(n)%class)
      call CheckStop( errmsg )
    endselect

    !*** add to monthly and yearly average, and increment counters
    select case(f_3d(n)%class)
    case("MAX3DSHL","MAX3DADV")
    ! For the MAX3D possibilities, we store maximum value of the
    !   current day in the IOU_INST variables.
    !   These are then added into IOU_MON **only** at the end of each day.
    ! (NB there is an error made on 1st day used, since only 1st 6 hours
    !  are checked. Still, not much happens on 1st Jan.... ;-)
      if(End_of_Day)then

        ! only accumulate outputs if they are wanted (will be written out)
        do iou=1,LENOUT3D
          if(iou==IOU_INST)cycle
          if(.not.wanted_iou(iou,f_3d(n)%iotype,ONLY_IOU))cycle
          d_3d(n,:,:,:,iou) = d_3d(n,:,:,:,iou) + d_3d(n,:,:,:,IOU_INST)
          if(f_3d(n)%avg) nav_3d(n,iou) = nav_3d(n,iou) + 1
        enddo

        if( dbgP ) then
          write(*,fmt="(a20,a9,i4,f8.3,2es12.3)") "END_OF_DAY MAX3D", &
            f_3d(n)%class, n, thour,  &
            d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_MON ),&
            d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_INST )
          write(*,"(a20,i4,2x,6i6)") "END_OF_DAY NAV ", &
            n, (nav_3d(n,i), i=1,LENOUT3D)
        endif
    
        d_3d(n,:,:,:,IOU_INST ) = 0.0  !! Reset d_3d
    
      endif ! End_of_Day
    case default

      af = 1.0 ! accumulation factor
      if(f_3d(n)%dt_scale) af=dt_advec !need to scale with dt_advec

      ! only accumulate outputs if they are wanted (will be written out)
      do iou=1,LENOUT3D
        if(iou==IOU_INST)cycle      
        if(.not.wanted_iou(iou,f_3d(n)%iotype,ONLY_IOU))cycle
        d_3d(n,:,:,:,iou) = d_3d(n,:,:,:,iou) + d_3d(n,:,:,:,IOU_INST)*af
        if(f_3d(n)%avg) nav_3d(n,iou) = nav_3d(n,iou) + 1
      enddo

    endselect
  enddo
  first_call = .false.
end subroutine Derived
!=========================================================================
subroutine DerivedProds(text,dt)
!*** DESCRIPTION
!  Calculates chemical changes by comparing values before and  after
!  chemistry subroutine. Intended to be a more flexible version of the old
!  PRODO3  calculation

  character(len=*), intent(in) :: text  ! "Before" or "After"
  real,             intent(in) :: dt    ! timestep (s)
  real :: timefrac                      ! dt as fraction of hour (3600/dt)
  integer :: index



! if ( num_deriv3d < 1 ) print *, "DerivedProds "//text, num_deriv3d
  if ( num_deriv3d < 1 ) return
  if (.not. any( f_3d%class == "PROD" ) ) return

  timefrac = dt/3600.0

!****** 3-D fields **************************
  do n = 1, num_deriv3d
    if(f_3d(n)%class/="PROD")cycle
    index = f_3d(n)%index
    select case ( text )
    case("Before")    !! Initialise to xn_adv
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=xn_adv(index,i,j,lev3d(k))
    case("After")     !! Calculate change
      forall(i=1:limax,j=1:ljmax,k=1:num_lev3d) &
        d_3d(n,i,j,k,IOU_INST)=d_3d(n,i,j,k,IOU_INST)&
                              -xn_adv(index,i,j,lev3d(k))
    endselect
  enddo
endsubroutine DerivedProds
!=========================================================================
subroutine ResetDerived(period)
  integer, intent(in) :: period   ! Either IOU_DAY or IOU_MON

  if(num_deriv2d>0 .and. period<=LENOUT2D) then
    nav_2d  (:,period) = 0
    d_2d(:,:,:,period) = 0.0
  endif

  if(num_deriv3d>0 .and. period<=LENOUT3D) then
    nav_3d    (:,period) = 0
    d_3d(:,:,:,:,period) = 0.0
  endif

endsubroutine ResetDerived
!=========================================================================
subroutine voc_2dcalc()
!/-- Sums up voc species using the indices defined earlier in Setup_VOCs
  integer :: index

! We initialise d_2d first, the use a simple loop
! over voc. Some CPU could be saved by initialising
! with the 1st voc, then looping over 2, nvoc, but who cares...

  d_2d( n, 1:limax,1:ljmax,IOU_INST) =  0.0

  do ivoc = 1, nvoc
    index = voc_index(ivoc)           ! Gives which IXADV_ to use.
    forall(i=1:limax,j=1:ljmax) &
      d_2d(n,i,j,IOU_INST)=d_2d(n,i,j,IOU_INST) &
                    +xn_adv(index,i,j,KMAX_MID) &
                     *voc_carbon(ivoc)*cfac(index,i,j)
                     ! multiplied by nr. of C and "reduced to surface"
  enddo ! ivoc
endsubroutine voc_2dcalc
!=========================================================================
subroutine voc_3dcalc()
!/-- as for voc_2dcalc
  integer :: index

  d_3d(n,1:limax,1:ljmax,1:num_lev3d,IOU_INST) =  0.0
  do ivoc = 1, nvoc
    index = voc_index(ivoc)
    forall(i=1:limax,j=1:ljmax,k=1:num_lev3d)  &
      d_3d(n,i,j,k,IOU_INST)=d_3d(n,i,j,k,IOU_INST) &
                      +xn_adv(index,i,j,lev3d(k))&
                       *voc_carbon(ivoc)
  enddo ! ivoc

 endsubroutine voc_3dcalc
!=========================================================================
subroutine group_calc( g2d, density, unit, ik, igrp,semivol)

  !/--  calulates e.g. SIA = SO4 + pNO3_f + pNO3_c + aNH4
  ! (only SIA converted to new group system so far, rv3_5_6 )
  !/--  calulates also PM10  = SIA + PPM2.5 + PPMCOARSE

  real, dimension(:,:), intent(out) :: g2d  ! i,j section of d_2d arrays
  real, intent(in), dimension(LIMAX,LJMAX)  :: density
  character(len=*), intent(in) :: unit
  integer, intent(in) :: ik,igrp
  logical, intent(in), optional :: semivol

  integer, pointer, dimension(:) :: gspec=>null()       ! group array of indexes
  real,    pointer, dimension(:) :: gunit_conv=>null()  ! & unit conv. factors
  logical :: needroa
  integer :: kk, iadv, itot, nspec ! FSOA
  real :: fac                      ! FSOA
  logical ::  semivol_wanted       ! FSOA
  logical ::  first_call    = .true.  ! FSOA
  logical ::  first_semivol_call = .true.  ! FSOA

!FSOA changes
  kk = ik
  if(ik==0) kk = KMAX_MID

  semivol_wanted=.false.
  if(present(semivol)) semivol_wanted = semivol
  
  if(DEBUG%DERIVED .and.debug_proc) &
    write(*,"(a,L1,3i4,2a16,L2)") "DEBUG GROUP-PM-N",debug_proc,me,ik, kk, &
      trim(chemgroups(igrp)%name), trim(unit), semivol_wanted

  call Group_Units(igrp,unit,gspec,gunit_conv,&
    debug=DEBUG%DERIVED.and.debug_proc,needroa=needroa)

  if(semivol_wanted.and.debug_proc) then
!    write(*,"(a,L1,2i4,2a16)") "DEBUG GROUP-FSOA",debug_proc,me,ik, &
!      trim(chemgroups(igrp)%name)
!    write(*,"(a,2i4)") "DEBUG GROUP-FSOA", size(gspec), size(gunit_conv)
!    write(*,*) "DEBUG GROUP-FSOA-GSPEC", gspec
!    write(*,*) "DEBUG GROUP-FSOA-GUNIT", gunit_conv
  endif

  do j=1,ljmax
    do i = 1, limax
      g2d(i,j) = 0.0
      do nspec = 1, size(gspec)
        iadv  = gspec(nspec) 
        itot  = iadv + NSPEC_SHL
        fac = 1.0

        ! With SOA modelling some compounds are semivolatile and others 
        ! non-volatile. If in a group XXX which asks for ugPM the latter's
        ! mass is correct. If semivolatile, we need to calculate the PM
        ! fraction and just add this.

        if(first_call.and.debug_proc) write(*,"(a,3i4,2(1x,a),2i4)") &
          "FSOA check ", nspec, itot, igrp, trim(chemgroups(igrp)%name),&
          trim(species(itot)%name), FIRST_SEMIVOL, LAST_SEMIVOL

        if(all([semivol_wanted,itot>=FIRST_SEMIVOL,itot<=LAST_SEMIVOL])) &
          fac = 1 - Fgas3d(itot,i,j,kk)

        if(ik==0) &
          fac = fac * cfac(iadv,i,j)

        if(all([first_semivol_call,debug_proc,chemgroups(igrp)%name=='BSOA']))&
          write(*,"(a,2i4,1x, es12.3, f12.5, 2x, a)") &
            "FSOA fac ", nspec, itot, fac, &
            xn_adv(iadv,i,j,kk)  * gunit_conv(nspec) * fac,  &
            trim(species(itot)%name)

        g2d(i,j) = g2d(i,j) + xn_adv(iadv,i,j,kk)  * gunit_conv(nspec) * fac
      enddo ! nspec
      if( first_semivol_call .and. semivol_wanted) first_semivol_call = .false.
      first_call = .false.
    enddo ! i
  enddo ! j
       

  if(needroa)&
    forall(i=1:limax,j=1:ljmax) &
      g2d(i,j) = g2d(i,j) * density(i,j)
  deallocate(gspec,gunit_conv)
endsubroutine group_calc
!=========================================================================
subroutine somo_calc( n, iX, debug_flag )
!/-- Calculates SOMO (8hours) values for input threshold.

  implicit none
  integer, intent(in) :: n           ! index in Derived_ml::d_2d arrays
  integer, intent(in) :: iX          !  threshold, usually 35 ppb
  logical, intent(in) :: debug_flag

  real :: o3                         ! Ozone (ppb) - needed if SOMOs
  real :: sum8h
  integer, parameter :: N8h = (NTDAY*8)/24 !number of periods in 8 hours
  real, parameter :: N8h_inv=1./N8h
  integer :: nh

  do i=1,limax
    do j=1,ljmax

      !find max running 8h sum O3
      sum8h=0.
      do nh=1,N8h
        sum8h = sum8h + D2_O3_DAY( i , j , nh)
      enddo
      o3=sum8h
      do nh=N8h+1,NTDAY
        sum8h =sum8h-D2_O3_DAY( i , j , nh-N8h)+D2_O3_DAY( i , j , nh)
        o3=max(o3,sum8h)
        if(n<0)write(*,*)o3 !pw fake for compiler!!
      enddo

      !divide by N8h to find 8h mean
      o3=o3*N8h_inv

      if(debug_flag.and.i==debug_li.and.j==debug_lj)&
        write(*,"(a,2i4,f12.3)") "SOMO DEBUG ", n, iX, o3


      o3 = max( o3 - iX , 0.0 )   ! Definition of SOMOs

      ! d_2d values will be accumulated in Derived_ml
      d_2d(n, i,j,IOU_DAY ) = o3

    enddo
  enddo
endsubroutine somo_calc
!=========================================================================
subroutine write_debugadv(n,index,rho,txt)
  integer, intent(in) :: n, index
  real, intent(in) :: rho
  character(len=*) :: txt

  write(*,"(2a,2i4,2a,4f12.3)") "PROCESS " , trim(txt) , n, index  &
    ,trim(f_2d(n)%name),trim(f_2d(n)%unit)  &
    ,d_2d(n,debug_li,debug_lj,IOU_INST)*PPBINV &
    ,xn_adv(index,debug_li,debug_lj,KMAX_MID)*PPBINV &
    ,rho, cfac(index,debug_li,debug_lj)
endsubroutine write_debugadv
!=========================================================================
subroutine write_debug(n,index,txt)
  integer, intent(in) :: n, index
  character(len=*) :: txt

  write(*,"(2a,2i4,a,4g12.3)") "DERIV: GEN " , txt , n, index  &
    ,trim(f_2d(n)%name),d_2d(n,debug_li,debug_lj,IOU_INST)
endsubroutine write_debug
!=========================================================================
endmodule Derived_ml
